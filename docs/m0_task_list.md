# Shardkeep — M0 Task List

Oct 20, 2026 · @Tyler MacPherson

## Overview

M0 is the playable prototype from the [design doc](https://claude.ai/code/artifact/1e8c8148-43f9-4431-8618-a899c907cd6c): one battle on the shared board against Easy and Normal AI, with placeholder art. It exists to answer two questions before any content work: are battles fun, and is GDScript fast enough for the AI.

A task is done when every acceptance box is ticked and CI is green. Tasks build on each other as shown below; T2 and T3 can go in either order, and so can T7 and T8.

&#91;embedded content: task dependencies · T1 through T11\]

## T1 · Project skeleton and CI

Set up the Godot 4 project, folder layout, test framework and CI so every later task lands with tests running from day one.

- Create the project with the `res://` layout from the design doc (`engine/`, `content/`, `schemas/`, `client/`, `autoload/`, `tools/`, `tests/`)
- Install GUT and add a command-line test entry point
- Add `ContentLoader` (plain class) and the `ContentDB` autoload that wraps it; load `gems.json`
- GitHub Actions on every push: JSON Schema check, `content_lint.gd`, engine purity lint, GUT in headless Godot

**Acceptance criteria**

- [ ] `godot --headless` runs the GUT suite locally and in CI; one placeholder test passes
- [ ] Adding `get_tree()` or `randi()` to any file in `engine/` fails the purity lint
- [ ] A malformed `gems.json` (wrong type, missing field) fails the schema check in CI
- [ ] A tool script started with `--script` loads content through `ContentLoader` without autoloads

## T2 · Deterministic random streams

Build the counter-based `mix` hash and stream API that every random choice in the engine will use.

- `mix(seed, stream, n)`: 32-bit integer hash in GDScript, each multiply split into 16-bit halves so 64-bit `int` math never overflows
- Stream helpers: `next_int`, `next_weighted(weights)`, each advancing a counter in the state
- Gem weight table loaded from `gems.json`

**Acceptance criteria**

- [ ] A golden table of 20 `(seed, stream, n)` → value pairs passes on every run and in CI
- [ ] 100,000 weighted draws land within ±1% of the configured gem weights
- [ ] Different streams with the same seed and n produce unrelated values (no two of the first 1,000 values match position by position across streams)
- [ ] Nothing in `engine/` uses `RandomNumberGenerator` or global random functions

## T3 · Board model and match detection

Implement the state classes and the match detector, tested entirely with golden boards before any gems fall.

- `BattleState`, `Board`, `SideState` as typed `RefCounted` classes with `clone()`
- Golden board text format and parser for tests (`R B G Y S A $ W ? .` for the gem types, `?` = `UNKNOWN`, `.` = `EMPTY`)
- Run scan per gem type, union-find grouping, group classification from the match table

**Acceptance criteria**

- [ ] Golden-board tests for every row of the match table: straight 3, 4, 5+, L, T, skull 4+
- [ ] A `WILD` between a red run and a blue run completes both, and they stay two groups
- [ ] Three `WILD`s alone don't match; `WILD` never joins skull, action or gold runs
- [ ] `UNKNOWN` and `EMPTY` never match
- [ ] Mutating a clone leaves the original's board and sides unchanged

## T4 · Swaps, cascades and skyfall

Wire up `Rules.apply()` for swaps: the core loop of match, pay, clear, fall and refill, emitting events as it goes.

- `legal_actions()` for swaps (adjacent pairs that create a match; locked gems excluded)
- Initial board from the `setup` stream: no ready-made matches, at least one legal swap
- Cascade loop: detect, pay base rewards to the acting side, clear, gravity, refill each column from its own stream
- Events: `swapped`, `matched`, `cleared`, `fell`, `spawned`, `resource_changed`, `turn_passed`

**Acceptance criteria**

- [ ] 1,000 generated boards each have no matches and at least one legal swap
- [ ] An illegal swap is rejected and the state is unchanged
- [ ] A golden-board test with a known seed produces an exact 3-step cascade with the expected rewards and event order
- [ ] Clearing cells in column 2 never changes which gems later fall in column 5
- [ ] All cascade rewards go to the acting side, at any cascade depth

## T5 · Specials, extra turns, KO and reshuffle

Add the rules that make the board interesting and the edge cases that end or stall a battle.

- Special creation and placement (`WILD`, `BURST`, `SKULL_BOMB`); `WILD` x2 multiplier; blast clears that pay out and chain
- Extra turn from any 4+ match, granted once per action
- Mid-cascade KO: stop the loop and end the battle; simultaneous KO means the acting side loses
- Reshuffle before any action with no legal swap, using the `shuffle` stream, with the 25% mana penalty and no lost turn
- Events: `special_created`, `extra_turn`, `reshuffled`, `battle_ended`

**Acceptance criteria**

- [ ] Golden-board tests for each special: created on the swapped cell, or lowest-then-leftmost in a cascade
- [ ] A `BURST` blast that hits a `SKULL_BOMB` triggers the bomb in the same step
- [ ] Two 4-matches in one cascade grant exactly one extra turn
- [ ] A cascade that drops the enemy to 0 HP stops immediately and emits `battle_ended`
- [ ] A dead board (no legal swap) reshuffles before the next action, including at the start of an extra turn; after 100 forced reshuffles every result has no matches and a legal swap

## T6 · Effects, spells, weapon and statuses

Build the `EffectRunner` and just enough content for two prototype loadouts. The full status set waits for M1.

- Effect ops for M0: `damage`, `damage_per_gem`, `gain_mana`, `convert_gems`, `apply_status`, `extra_turn`
- `Cast` and `Attack` actions, mana and action-point costs, cooldowns, `ends_turn` (a swap is allowed after a non-ending spell)
- Status hooks (`on_turn_start`, `on_gain`, `on_damage_taken`, `on_turn_end`) with three statuses: stun, burn, barrier
- Spell-granted extra-turn chain cap of 2; anti-stunlock rule; stunned side passes
- Content: `spells.json`, `weapons.json`, `statuses.json`, `classes.json` with two loadouts (placeholder names and numbers)

| Loadout | Spell 1 | Spell 2 | Weapon |
| --- | --- | --- | --- |
| A | Firebolt: damage per red gem on the board | Tidal Shift: convert green to blue, doesn't end turn | Sword |
| B | Stone Barrier: barrier status | Concussion: damage + 1-turn stun | Mace |

**Acceptance criteria**

- [ ] Each effect op has a unit test, including a `convert_gems` that triggers a cascade paid to the caster
- [ ] Casting with too little mana, or on cooldown is not in `legal_actions()`
- [ ] Stun makes the target pass; a second stun on the next turn is blocked; statuses tick down on a skipped turn
- [ ] Barrier absorbs skull and weapon damage before HP
- [ ] A test spell granting extra turns stops after 2 in a row
- [ ] Content validation passes for all M0 files and fails on an unknown effect op

## T7 · AI

Implement the AI search on top of `apply()`, with fog simulation so it can only use what the player can see.

- `sim_draw_budget` set to 1 per column at the search root; draws past it return `UNKNOWN`
- Scoring function with weights from the enemy's content entry; mana need based on equipped spell costs
- Easy (1 ply, seeded noise), Normal (own action + player's best reply), Hard (3 ply, beam of 6) as a benchmark
- Extra-turn continuations chosen greedily instead of branching
- Search runs as a `WorkerThreadPool` task; minimum 500 ms think time in the client

**Acceptance criteria**

- [ ] Fog test: changing what falls after the ghost row, with the board, the ghost row and the AI's own stream held fixed, never changes the AI's decision
- [ ] Normal never picks a move that leaves the player a 4-match when an equally scored move doesn't (golden-board test)
- [ ] Given a lethal swap, every level takes it
- [ ] Same seed and state give the same AI decision every time
- [ ] Search never mutates the real state (hash before equals hash after)
- [ ] A `benchmark.gd` tool reports average and worst-case decision time for each level over 200 positions

## T8 · Battle screen and event playback

Build the playable screen with placeholder art: input becomes actions, and events become animation.

- `BoardView` with a distinct shape and color per gem, click-to-swap and drag-to-swap, illegal swaps snapping back
- Ghost row above the board showing each column's next gem
- `SidePanel` (HP, four mana bars, action points, statuses), `SpellBar`, weapon button
- `EventPlayer` with 1×, 2× and instant speeds; input locked during playback
- `BattleController`: turn flow, AI on a worker thread, win and loss screens, difficulty picker (Easy, Normal)
- Battle seed shown on screen

**Acceptance criteria**

- [ ] A full battle against Easy and Normal can be played start to finish with mouse only
- [ ] Instant speed shows the same final board as 1× for the same moves
- [ ] Clicking during playback or the AI's turn does nothing
- [ ] The UI stays responsive (no frame hitch over 50 ms) while the AI thinks
- [ ] Every gem type is distinguishable in grayscale

## T9 · Replay and fuzz tests

Make every battle reproducible from a seed and a move list, and hammer the rules with AI-vs-AI play to catch what unit tests miss.

- Canonical byte serialization of `BattleState` (fixed field order, packed arrays as raw bytes) and a SHA-256 via `HashingContext`
- Debug key that exports seed, loadouts and action list to a JSON file
- `replay.gd`: replays an export headless and prints the final state hash
- Fuzz test: random loadouts, Easy AI on both sides, invariants checked after every action

**Acceptance criteria**

- [ ] 3 replay fixtures from real played battles pass in CI
- [ ] Changing one gem weight makes the affected fixtures fail with a clear message
- [ ] Fuzz test runs 10,000 actions with zero invariant failures: full board with no ready matches and a legal swap before every action, no `UNKNOWN` outside simulation, HP and mana within bounds, `clone()` + `apply()` never changes the original, replay reproduces the same hash
- [ ] A failing fuzz run writes its seed and action list, so it can be replayed directly

## T10 · Balance runner

Build the headless tool that plays thousands of AI-vs-AI battles and flags anything out of range.

- `balance_runner.gd`, run with `godot --headless --script`, taking a matchups file and a game count
- Matchups: loadout A vs B, A vs A, B vs B, at a chosen AI level; seeds derived from a base seed
- CSV per matchup: win rate, first-mover win rate, average turns, longest extra-turn chain, share of spell casts, reshuffles per battle, plus the seed of the most extreme battle
- Flags from the design doc's thresholds printed at the end
- CI smoke run of 200 games

**Acceptance criteria**

- [ ] 1,000 Easy-vs-Easy battles complete headless and write the CSV
- [ ] Running twice with the same base seed gives identical CSVs
- [ ] A deliberately broken loadout (a free spell dealing 50 damage) is flagged on win rate
- [ ] The extreme battle replays exactly from its seed, loadouts and AI levels
- [ ] The CI smoke run finishes in under 5 minutes

## T11 · Measure and fun check

Answer the two questions M0 exists for, record the results in the design doc, and make the exit decision.

- Run `benchmark.gd` on a desktop PC and on the slowest machine you plan to support
- Play 30 battles across both loadouts and both difficulties; after each, write one line on what felt good and one on what felt bad
- Run the balance runner on all matchups at Normal and review the flags

**Acceptance criteria**

- [ ] Average `apply()` time and Easy, Normal and Hard decision times recorded in the design doc for both machines
- [ ] First-mover win rate checked; if above 55%, the second-player mana head start is added and re-tested
- [ ] 30 battle notes written, with the 3 most common complaints pulled out
- [ ] Exit decision recorded in the design doc: move to M1, port the engine to C#, or tune board rules and repeat the fun check
