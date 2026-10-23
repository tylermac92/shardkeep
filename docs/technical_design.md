# Shardkeep — Technical Design

Oct 20, 2026 · @Tyler MacPherson

## Overview

The game is built around one pure, deterministic rules engine written in GDScript. The Godot client, the AI and the headless test tools all drive that same engine. This doc covers the battle core and the systems the MVP needs; dungeons, citadel and gear reuse it later. It follows the [product brief](https://claude.ai/code/artifact/a594b3fc-5419-4577-8295-2c6f46de24e1).

**Key decisions**

- **Pure engine.** `apply(state, action)` returns a new state plus a list of events. No nodes, no signals, no timers, no global RNG. Same input, same output, every time.
- **Events drive animation.** The client never inspects how rules work; it replays the event list (gems matched, gems fell, damage dealt) at the chosen animation speed.
- **Per-column seeded skyfall.** Each column has its own random stream fixed at battle start, and the next gem in each column is visible to both sides.
- **Fog-of-war simulation for the AI.** When the AI simulates moves, any gem beyond the visible preview is an "unknown" gem that never matches, so the AI physically can't use hidden information.
- **Content as JSON.** Spells, enemies and classes are data, validated at load and in CI.
- **GDScript first, C# if needed.** The engine is isolated enough to port to C# inside Godot if AI search or balance runs prove too slow. The first milestone measures this.

Out of scope here: save format, dungeon and overworld flow, gear, capture puzzles and the citadel. Each gets a short design section once the battle core is proven.

## Architecture

The engine sits in the middle and depends on nothing but content definitions; the client and the headless tools are both just callers.

&#91;embedded content: architecture · engine, content, client and tools\]

The client sends an action and gets back a new state plus the events to animate. The tools replay seeds and action lists without any scene tree, which is what makes balance runs and replay tests cheap.

## Game state

All battle state lives in one `BattleState` object that is cheap to clone, because the AI clones it hundreds of times per decision. Everything is a typed `RefCounted` class, not a `Node`.

```
BattleState
  board: Board
  sides: Array[SideState]        # [0] = player, [1] = enemy
  active_side: int
  turn: int
  extra_turn_chain: int          # spell-granted extra turns this chain (cap 2)
  col_draws: PackedInt32Array    # skyfall values used per column (8)
  stream_draws: PackedInt32Array # values used per other stream (setup, shuffle, effects, ai, loot)
  sim_draw_budget: PackedInt32Array  # AI search only: draws left per column, -1 = unlimited
  battle_seed: int
  result: int                    # ONGOING, SIDE0_WON, SIDE1_WON

Board (8 x 8, index = y * 8 + x, y = 0 is the top row)
  gems: PackedByteArray          # RED BLUE GREEN YELLOW SKULL ACTION GOLD WILD UNKNOWN EMPTY
  special: PackedByteArray       # NONE BURST SKULL_BOMB
  locked: PackedByteArray        # turns remaining; 0 = free

SideState
  hp, hp_max: int
  mana: PackedInt32Array         # 4 colors
  mana_cap: PackedInt32Array
  action_points, gold_gained: int
  stats: Stats                   # mastery x4, might, vitality, cunning
  spells: Array[StringName]      # content ids, up to 6
  cooldowns: PackedInt32Array
  weapon: StringName
  statuses: Array[StatusInstance]
```

`clone()` copies the packed arrays and the small arrays. Randomness is stored only as counters (see Randomness), so a clone holds no RNG objects and a simulated move can never advance the real game's streams. Content definitions are shared by reference and never mutated.

**Actions** are small value objects: `Swap(a, b)`, `Cast(spell_id, target)`, `Attack()`, and `Pass()`, which is only used when the acting side is stunned. `legal_actions(state)` lists every legal action for the active side; the client uses it to validate input and the AI uses it to generate moves.

**Events** are what the client animates and what the battle log shows. Each is a small dictionary with a `type` and fields, emitted in order:

| Event | Fields |
| --- | --- |
| `swapped` | a, b |
| `matched` | cells, gem, group\_size, cascade\_depth |
| `special_created` | cell, kind |
| `cleared` | cells, cause (match, spell, burst, bomb) |
| `fell` | moves (from, to) |
| `spawned` | cells, gems |
| `resource_changed` | side, kind (hp, mana color, ap, gold), delta |
| `status_applied` / `status_expired` | side, status, turns |
| `spell_cast` | side, spell, target |
| `extra_turn` | side, reason |
| `reshuffled` | new board, mana penalty |
| `turn_passed` | to\_side |
| `battle_ended` | winner |

State plus events also give a battle log for free, which supports the brief's post-battle "who got which cascades" view.

## Turn pipeline

Every action runs the same pipeline inside `apply()`: resolve the action, loop on matches until the board settles, then decide whose turn it is.

&#91;embedded content: turn pipeline · cascade loop, extra turns, end of turn\]

The cascade loop pays the acting side for everything it causes, however deep. If either side reaches 0 HP during the loop, the loop stops and the battle ends at once; if both reach 0 on the same action, the acting side loses. An extra turn is decided once per action, after the board settles, and spell-granted extra turns count toward the chain cap of 2. Status damage at the start of a turn can also end the battle, so the win check runs there too, and the no-move reshuffle check runs before every action.

## Match rules

Match detection finds runs of 3+ in rows and columns, then merges runs that share a cell into groups; the group's shape decides rewards and special gems.

**Detection**

1. Scan each row and column for runs of 3 or more. `UNKNOWN` and `EMPTY` never match. `WILD` counts as any mana color: the scan runs once per color with `WILD` treated as that color, so one `WILD` can complete a red run and a blue run at once (it's cleared once and multiplies both). A run needs at least one real colored gem, and skulls, action gems and gold can't use `WILD`.
2. Merge runs of the same gem type that share at least one cell into a group (union-find over the 64 cells, one pass per gem type so a shared `WILD` doesn't merge two colors).
3. Classify each group:

| Group | Rule | Result |
| --- | --- | --- |
| Straight 3 | One run of 3 | Normal reward |
| Straight 4 | One run of 4 | Reward + extra turn |
| Straight 5+ | One run of 5 or more | Reward + extra turn + `WILD` gem |
| L or T | Horizontal and vertical runs joined, 5+ cells | Reward + extra turn + `BURST` gem |
| Skull 4+ | Any skull group of 4 or more | Damage + `SKULL_BOMB` gem (+ extra turn by the rules above) |

**Where specials appear.** On the swapped cell if it belongs to the group; in a cascade, on the group's lowest, then leftmost cell. That rule is fixed so replays stay deterministic. `BURST` and `SKULL_BOMB` sit on top of the group's gem type (a red `BURST` still matches as red); `WILD` replaces the gem.

**Rewards.** Each matched gem pays its base value (1 mana, 1 action point, gold or skull damage per the content table) to the active side, multiplied by any `WILD` in the group (x2) and modified by mastery stats. Skull damage goes through the target's barrier first. Extra turns from 4+ matches are only granted once per action, however many qualify in the cascade.

**Specials when matched.** `BURST` clears its 3×3 area; `SKULL_BOMB` clears its 3×3 area and deals bonus damage. Gems cleared by a blast pay their rewards, so blasts can chain into other specials.

**No valid moves.** Before every action, including an extra turn, the engine checks that the acting side has a legal swap. If not, the board reshuffles: the existing gems are permuted using the `shuffle` stream until the board has no ready-made matches and at least one legal swap (max 100 tries, then a fresh board from the skyfall streams). Both sides then lose 25% of each mana pool, rounded down. The reshuffle doesn't cost the acting side its turn.

## Randomness

Every random choice in a battle comes from a named stream derived from one 64-bit battle seed, so a seed plus a move list reproduces a battle exactly.

| Stream | Used for | n-th value |
| --- | --- | --- |
| `col_0` … `col_7` | Skyfall, one per column | mix(seed, "col", x, n) |
| `setup` | Initial board | mix(seed, "setup", n) |
| `shuffle` | Reshuffles | mix(seed, "shuffle", n) |
| `effects` | Spells with random targets | mix(seed, "effects", n) |
| `ai_0`, `ai_1` | AI tie-breaks and Easy-mode noise | mix(seed, "ai", side, n) |
| `loot` | Post-battle gold and drops | mix(seed, "loot", n) |

Streams are counter-based, not stateful: the n-th value of a stream is a pure hash of the seed, the stream name and n, and the state only stores how many values each stream has used. `mix` is a small 32-bit integer hash written in GDScript (for example a murmur3 finalizer, with each multiply split into 16-bit halves so GDScript's signed 64-bit ints never overflow). This avoids Godot's `RandomNumberGenerator` objects, which are reference-counted and would silently be shared between a state and its clone, and keeps results independent of Godot's RNG implementation across engine versions. Streams are kept separate so that, for example, a randomly targeted spell never shifts which gems fall next.

**Gem weights.** Each spawn rolls against a weight table from content (default: each mana color 16%, skull 12%, action 12%, gold 12%). Weights can vary per battle for flavor, such as a skull-heavy undead crypt.

**Per-column skyfall and preview.** When a column needs N new gems, it takes the next N from its own stream. The next gem in every column is shown above the board as a ghost row, so both sides see the same 8 upcoming gems. One stream per column means the preview stays correct however many gems fall elsewhere.

**Fog simulation.** When the AI starts a search, it copies the root state and sets `sim_draw_budget` to 1 for every column. Each skyfall draw in a simulated state spends that column's budget; once it's spent, further draws return `UNKNOWN`, which never matches. The budget is counted from the search root, not per `apply()`, so a 3-ply search can't see deeper into a column on ply 2 or 3 than the player can see right now. In real play the budget is -1 (unlimited) and `UNKNOWN` never appears.

## Effects, spells and status

Spells, weapons, statuses and later gear all compile down to one small vocabulary of effect ops, run by a single `EffectRunner`. New content is new data, not new code, until an effect needs an op that doesn't exist yet.

**Effect ops (MVP set)**

| Op | Parameters | Notes |
| --- | --- | --- |
| `damage` | target, amount | Goes through barrier |
| `damage_per_gem` | target, gem, per | Counts gems on the board at cast time |
| `heal` | target, amount | Capped at max HP |
| `gain_mana` / `drain_mana` / `steal_mana` | target, color, amount | Steal = drain + gain |
| `gain_ap` | target, amount |  |
| `convert_gems` | from, to, count (or all) | Random picks use the `effects` stream |
| `destroy` | row, column, color or area | `collect` flag decides if destroyed gems pay out |
| `lock_gems` | count, turns | Locked gems can't be swapped |
| `apply_status` | target, status, turns, stacks |  |
| `extra_turn` |  | Counts toward the chain cap of 2 |

Any op that changes the board is followed by the normal cascade loop. Cascades pay the caster. Gems an effect destroys pay nothing unless the effect sets `collect: true`, so destruction spells are about board shape, not free mana.

**Spells** have a mana cost per color, an optional cooldown, `ends_turn` (default true) and a list of effects. `can_cast` checks mana, cooldown and silence.

**Weapons** are spells with an action-point cost instead of mana, always available through `Attack()`.

**Statuses** are data with hooks. The engine calls hooks at fixed points only:

- `on_turn_start(owner)`: burn and poison damage, stun check (stunned side passes)
- `on_gain(owner, resource, amount)`: freeze blocks a mana color
- `on_damage_taken(owner, amount)`: barrier absorbs
- `on_turn_end(owner)`: duration ticks down, expiry

All statuses tick at the end of their owner's turn, including a turn skipped by stun. Stun can't be applied to a side that was stunned on its previous turn (the anti-stunlock rule). Gear and companion passives will use the same hooks later, which keeps every rule change in one place.

## AI

The AI plays by simulating candidate actions with the same `apply()` the player uses, under fog simulation, then scoring the resulting states. It has no special access to the board, the streams or the player's hand.

**Move generation.** `legal_actions()` returns every legal swap (typically 5–20 of the 112 adjacent pairs), every castable spell with each valid target, and `Attack()` if affordable.

**Scoring.** A state is scored from the AI's point of view as a weighted sum. Weights live in content, so each enemy can have a personality (an aggressive orc weights damage higher, a shaman weights mana).

```latex
score = w_{dmg} \Delta hp_{enemy} - w_{hurt} \Delta hp_{self} + \sum_c w_c(need_c) \Delta mana_c + w_{ap} \Delta ap + w_{xt} \cdot extra\_turn + w_{status} \cdot status\_value
```

The mana weight per color depends on need: mana that brings an equipped spell within reach is worth more than mana for a full pool. A won battle scores as infinity.

**Difficulty levels**

| Level | Search | Notes |
| --- | --- | --- |
| Easy | 1 ply: best immediate score | Adds seeded noise; 25% of the time picks the 2nd or 3rd best |
| Normal | 2 ply: own action, then the player's best reply | Avoids leaving 4-matches and big cascades for the player |
| Hard | 3 ply with a beam of 6 at each level | Plans spell timing, sets up its own 4-matches |

**Extra turns and plies.** An extra turn keeps the same side on the same ply, but the continuation is chosen greedily (best immediate score) instead of branching, so a long chain can't blow up the search. Ties break on the AI's own seeded stream.

**Performance budget.** Hard must decide in under 250 ms on a Steam Deck. The search runs on a `WorkerThreadPool` task so the UI never stalls, and the client waits at least 500 ms before acting so the AI doesn't feel instant. Measuring per-`apply()` cost in GDScript is part of the first milestone; if Hard misses budget, shrink the beam first, then port the engine to C#.

## Content schema

Content lives as JSON under `res://content/`, one file per type, loaded once at startup by a `ContentDB` autoload into typed definition objects. JSON over Godot `.tres` resources because it diffs cleanly, is easy to generate or bulk-edit with scripts, and can be validated outside Godot in CI.

**Spell**

```json
{
  "id": "fireball",
  "name": "Fireball",
  "classes": ["reaver"],
  "cost": { "red": 8 },
  "cooldown": 0,
  "ends_turn": true,
  "effects": [
    { "op": "damage", "target": "enemy", "amount": 6 },
    { "op": "damage_per_gem", "target": "enemy", "gem": "red", "per": 1 }
  ]
}
```

**Enemy**

```json
{
  "id": "goblin_shaman",
  "name": "Goblin Shaman",
  "level": 3,
  "hp": 42,
  "mana_cap": { "red": 20, "blue": 15, "green": 25, "yellow": 15 },
  "stats": { "might": 2, "cunning": 3 },
  "spells": ["poison_dart", "mend"],
  "weapon": "rusty_knife",
  "ai": { "level": "normal", "weights": { "damage": 1.0, "mana": 1.3 } },
  "xp": 30,
  "gold": [8, 15]
}
```

**Other MVP files:** `classes.json` (starting stats, stat costs, spell unlock levels), `statuses.json`, `weapons.json`, `gems.json` (base rewards and default spawn weights) and `battles.json` (enemy, weight overrides, fixed seed for scripted fights).

Numbers above are placeholders for the shape, not balance targets.

**Validation** happens in two layers. CI checks each file against its JSON Schema in `schemas/` with a standard command-line validator (for example `check-jsonschema`), since Godot has no built-in JSON Schema support. `content_lint.gd` then checks references: every spell id an enemy lists exists, every effect op is known, every status named exists. The same reference checks run at load in debug builds. A bad content file fails CI, never a play session.

## Godot integration

The client is a thin layer: it turns input into actions, hands them to the engine, and plays back the events it gets in return. Rules never live in scenes.

**Battle flow in the client**

1. `BattleController` (a `Node`) owns the current `BattleState`.
2. On the player's turn, `BoardView` turns clicks or drags into a `Swap`; `SpellBar` and the weapon button produce `Cast` and `Attack`. Each is checked against `legal_actions()` before it's sent.
3. `BattleController` calls `Rules.apply()`, swaps in the new state immediately, and passes the events to `EventPlayer`. The engine's entry class is `Rules`, not `Engine`, which is already a Godot built-in singleton.
4. `EventPlayer` plays events in order with tweens. At 1× it waits for each animation, at 2× it halves durations, and at instant it jumps to the end. Input stays locked until playback finishes.
5. On the AI's turn, `BattleController` starts the AI search on a worker thread, waits for the result and the minimum think time, then goes back to step 3.

Because the state is already final when playback starts, animations can't desync rules: skipping or speeding up only changes what's on screen.

**Project layout**

```
res://
  engine/          # pure rules: state, pipeline, matches, effects, skyfall, ai
  content/         # JSON data
  schemas/         # JSON Schemas for content
  client/
    battle/        # BattleController, BoardView, EventPlayer, SpellBar, SidePanel
    ui/            # menus, settings
  autoload/        # ContentDB, Settings, Profile
  tools/           # balance_runner.gd, replay.gd, content_lint.gd
  tests/           # GUT tests and replay fixtures
```

A CI lint (grep with word boundaries) blocks `engine/` from using `Node`, `get_tree`, `Time`, `OS`, the global `randi`/`randf` functions, `RandomNumberGenerator`, any autoload, or any `client/` path. Content loading lives in a plain `ContentLoader` class that the `ContentDB` autoload wraps, so tools started with `--script` load content directly instead of depending on autoloads.

## Testing and balance

Determinism is what makes this game testable: every bug report and every balance question reduces to a seed plus a list of actions.

**Unit tests (GUT).** Match detection and cascades use golden boards written as text, so a test reads like the board it checks:

```
R B G Y S A $ R
R B G Y S A $ R
B R R G Y S A $
...
```

Covered: every group shape in the match table, special creation and placement, blasts chaining into other specials, reshuffle guarantees, skyfall per-column independence, each effect op and each status hook.

**Replay tests.** A fixture is a seed, both sides' loadouts and an action list, plus a SHA-256 of the final state. The hash comes from a canonical byte serialization (fixed field order, packed arrays as raw bytes) fed to Godot's `HashingContext`, not from `str()` or `hash()` on a dictionary, which aren't guaranteed stable across engine versions. If a rule change alters a replay, the diff is explicit and the fixture is updated on purpose. Any bug found in play becomes a replay fixture.

**Fuzz tests.** Thousands of AI-vs-AI turns with random loadouts, checking invariants after every action:

- The board is full and has no ready-made matches before every action
- The acting side has at least one legal swap before every action
- No `UNKNOWN` gem appears outside AI simulation
- HP never exceeds max; mana never exceeds cap or drops below 0
- `clone()` then `apply()` never changes the original state
- Replaying the recorded actions from the seed gives the same state hash

**Balance runner.** `godot --headless --script res://tools/balance_runner.gd -- --matchups m.json --games 1000` plays AI vs AI and writes a CSV per matchup:

| Column | Flag when |
| --- | --- |
| Win rate | Mirror match outside 45–55% |
| First-mover win rate | Above 55% in mirror matches (triggers a second-player mana head start) |
| Average turns per battle | Outside the 15–40 target (tuning) |
| Longest extra-turn chain | Above 6 |
| Share of turns that are spell casts | Below 10% (spells don't matter) |
| Reshuffles per battle | Above 1 |

Each row also records the seed of its most extreme battle, so a flagged result can be replayed and watched.

**CI.** GitHub Actions on every push: content validation, the engine purity lint, GUT tests and replay fixtures in headless Godot, plus a 200-game balance smoke run. A container image with Godot preinstalled, such as `barichello/godot-ci`, keeps setup to a few lines.

## First milestone: playable prototype

M0 answers two questions before any content work: is a battle on the shared board fun, and is GDScript fast enough for the AI. Art is placeholder shapes and colors throughout.

**Acceptance criteria**

- [x] 8×8 board renders with distinct placeholder shapes per gem; click-to-swap and drag-to-swap both work, and illegal swaps snap back
- [x] Full turn pipeline: matches (including `WILD` across two colors), all special gems, cascades, mid-cascade KO, extra turns with the chain cap, reshuffle before any action with no legal swap
- [x] Ghost row shows the next gem in each column
- [x] Player vs Easy and Normal AI, 2 spells and a weapon per side, HP and mana bars, win and loss screens
- [x] Animation speed toggle (1×, 2×, instant)
- [x] Battle seed shown on screen; a debug key exports seed plus action list, and `replay.gd` reproduces the battle to the same state hash
- [x] At least 30 GUT tests, including golden boards for every group shape, and 3 replay fixtures
- [x] Fuzz test runs 10,000 turns with zero invariant failures
- [x] Balance runner completes 1,000 Easy-vs-Easy battles headless and writes the CSV, including first-mover win rate
- [ ] Measured and recorded in this doc: average `apply()` time, plus Normal and Hard AI decision times (Hard as a benchmark only, not yet playable), on a desktop PC and the slowest target machine *(cloud sandbox only; skipped on real machines, see [M0 results](#m0-results))*
- [ ] Fun check: 30 battles played by you, with short notes on what felt good and what felt bad *(skipped)*

**Exit decision.** If the fun check is positive and the Hard benchmark fits its 250 ms budget, move on to M1 (classes, levels 1–10, the full status set, playable Hard AI). If Hard misses budget even with a smaller beam, port the engine to C# before M1. If the battles aren't fun, tune board rules (gem weights, skull damage, extra-turn rules) and repeat the fun check before adding content.

## M0 results

Recorded Oct 22–23, 2026. The fun check and the real-machine benchmarks were skipped; the exit decision was made without them.

### Speed

`godot --headless --script res://tools/benchmark.gd` (200 positions, decision times in ms, average / worst):

| Machine | `apply()` | Easy | Normal | Hard, beam 6 | Hard, beam 4 | Hard, beam 3 |
| --- | --- | --- | --- | --- | --- | --- |
| Cloud sandbox: Xeon 2.1 GHz, 4 cores, Godot 4.7.2 editor build | 0.72 | 14 / 124 | 119 / 991 | 316 / 965 | 171 / 454 | 101 / 310 |
| Desktop PC | *not measured* | | | | | |
| Slowest target (Steam Deck) | *not measured* | | | | | |

The beam is `AI.BEAM` in `engine/ai.gd` (6 today). Hard at beam 6 misses the 250 ms budget on the sandbox; beam 4 fits it on average but not in the worst case. A T10 change to swap checks cut Hard from 951 ms to 316 ms with identical results, so profiling found real headroom before any port.

GDScript threads in one process slow each other down in this build (four threads took about 3x longer than the same work run one after another), so the balance runner uses one process per core. The battle screen runs the AI on a single worker thread and isn't affected.

### First mover

Mirror matches, first-mover win rate:

| Run | A vs A | B vs B |
| --- | --- | --- |
| Easy, 1,000 games each, no head start | 60.5% | 59.1% |
| Easy, 500 games each, second mover starts with 3 mana per color | 47.4% | 51.2% |
| Easy, 500 games each, 6 mana per color | 38.4% | 51.6% |
| Easy, 1,000 games each, 3 mana (adopted) | 50.5% | 51.2% |
| Normal, 200 games each, 3 mana | 50.5% | 56.5% |

The head start is adopted at 3. Normal's B mirror is just over 55%, but at 200 games the margin is about ±3.5 points; re-check it with more games once the loadouts are tuned.

### Balance

`tools/balance_runner.gd`, all matchups, with the head start:

| Level | Matchup | A wins | First mover wins | Avg turns | Longest extra-turn chain | Spell casts | Reshuffles per battle |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Easy (1,000 games) | A vs B | 88.3% | 48.1% | 35.4 | 8 | 19.3% | 0.12 |
| Easy (1,000 games) | A vs A | 50.7% | 50.5% | 25.6 | 8 | 21.0% | 0.06 |
| Easy (1,000 games) | B vs B | 49.8% | 51.2% | 69.8 | 9 | 14.5% | 0.66 |
| Normal (200 games) | A vs B | 94.0% | 52.0% | 42.2 | 7 | 17.0% | 0.28 |
| Normal (200 games) | A vs A | 52.5% | 50.5% | 33.2 | 7 | 18.4% | 0.18 |
| Normal (200 games) | B vs B | 49.5% | 56.5% | 76.4 | 7 | 13.4% | 0.99 |

Flags to tune before content work:

- **Loadout A beats B** 88% (Easy) to 94% (Normal). Likely cause, not yet measured: Firebolt deals 1 damage per red gem on the board (about 9 for 7 mana), while B's Stone Barrier and Concussion mostly defend or deal 3.
- **B mirrors run 70 to 76 turns** (target 15 to 40), likely for the same reason: B has little direct damage.
- **Extra-turn chains reach 7 to 9** (flag above 6). The cap of 2 only covers spell-granted extra turns; 4-matches can chain without limit.

The two loadouts are placeholders, so these are tuning inputs for M1's real classes rather than board-rule failures.

### Fun check

Skipped. The notes form on the win and loss screen and [fun_check.md](fun_check.md) stay in place for a later playtest.

### Exit decision

Decided Oct 23, 2026 by the project owner: **move to M1**, without the fun check or the real-machine benchmarks.

- [x] Move to M1
- [ ] Port the engine to C#
- [ ] Tune board rules and repeat the fun check

Open risks carried into M1:

- **Hard's speed is unproven on target hardware.** M1 makes Hard playable. On the sandbox, beam 6 misses the 250 ms budget and beam 4 fits on average; measure on the Steam Deck before shipping Hard, and shrink the beam (or port to C#) if it misses.
- **Fun is unverified.** No one has played 30 battles yet, so board-rule problems may surface once M1's real classes are in.
- **The balance flags above are still open**, to be tuned with M1's real classes rather than the M0 placeholders.

## Decisions

The open questions from the first draft were settled with their proposed defaults on Oct 20, 2026.

| Question | Decision |
| --- | --- |
| Who moves first | Higher Cunning; ties broken by the seed. No second-player compensation unless the balance runner shows a first-mover win rate above 55%. M0 showed about 60%, so the second mover now starts with 3 mana of each color (`second_mover_mana` in `gems.json`; see [M0 results](#m0-results)) |
| Skull damage and Might | Start with a flat bonus per point of Might; tune with the balance runner in M0 |
| Swap after a non-ending spell | Allowed in the same turn |
| Cost of a reshuffle | Mana penalty only; no lost turn |
| Ghost row depth | 1 gem per column |
