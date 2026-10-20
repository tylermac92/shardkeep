# Puzzle Quest–Style Match-3 RPG — Product Brief

Oct 20, 2026 · @Tyler MacPherson

## Concept

**Working title: Shardkeep.** A single-player fantasy RPG where every fight, lock, forge and siege is played on one shared 8×8 match-3 board, turn by turn, against an AI that follows the same rules you do.

It takes Puzzle Quest 2's dungeon-first structure, action gems, weapon attacks and per-interaction minigames, and adds Puzzle Quest 1's "learn spells by capturing monsters" system and citadel. The setting is classic high fantasy with original names, factions and art. The hook stays the same as the originals: a casual-feeling puzzle board where the RPG layer (class, spells, gear) changes how the board plays, so leveling up feels like learning new puzzle tricks rather than just bigger numbers.

Target feel: a battle takes 3–6 minutes, a play session is 30–60 minutes, and a full campaign runs 25–35 hours. These are starting targets, not commitments.

It starts as a personal project in Godot 4, built to a standard that could ship on Steam later as a one-time purchase.

## Design pillars

The originals worked because both players share one board, so every move is also a gift or a denial to the opponent. Five pillars carry that forward and fix what players complained about.

1. **Shared board, shared risk.** You never just take the best match; you check what it leaves for the enemy. Setting up a cascade for yourself and leaving a dead board for them is the core skill.
2. **Spells bend the board.** Class identity comes from how you manipulate gems (convert colors, clear rows, lock tiles), not only from damage numbers.
3. **Everything is a puzzle.** Capturing, crafting, lockpicking and sieges each use the same board with a different rule set, so non-combat actions still feel like play.
4. **Fair, visible randomness.** Puzzle Quest 1's AI was widely accused of getting lucky skyfalls. New gems come from a seeded queue both sides draw from, and an optional "next drops" preview shows what's coming.
5. **Short fights, long arc.** Battles stay short; depth comes from builds, captured spells and gear combos across the campaign.

Also fixed from the originals: infinite extra-turn loops in late-game builds (capped chains), PQ2's dungeon backtracking (compact room graphs), and long unskippable animations (speed setting and skip).

## Core loop

Every step of the campaign leads to a board encounter, and every reward feeds back into the next one.

&#91;embedded content: core loop · campaign loop and battle turn loop\]

Inside a battle, a match of 4 or more sends the turn straight back to the same player; otherwise the enemy moves on the same board under the same rules.

## The board

An 8×8 grid with seven gem types; you swap two adjacent gems, and the swap must make a line of 3 or more. Matched gems pay their reward to whoever made the move, including every cascade that follows.

| Gem | Match of 3 gives | Notes |
| --- | --- | --- |
| Fire (red) | 3 red mana | Damage spells |
| Water (blue) | 3 blue mana | Control, freeze, healing |
| Earth (green) | 3 green mana | Defense, poison, armor |
| Air (yellow) | 3 yellow mana | Speed, extra turns, mana steal |
| Skull | 3 direct damage | Ignores spells; the main tempo weapon |
| Action (gauntlet) | 1 action point | Spent on weapon attacks (PQ2-style) |
| Gold | Gold | Buys gear, citadel upgrades |

Starting values are tuning defaults. XP is awarded only at the end of a battle, scaled by the enemy's level; there is no XP gem, which keeps every match a direct choice between mana, damage, action and gold.

**Match rules**

- Match 4 in a line: extra turn.
- Match 5 in a line: extra turn plus a wildcard gem that multiplies the next match it joins.
- L or T shapes (5 gems): extra turn plus a "burst" gem that clears its 3×3 area when matched.
- 4 or 5 skulls: creates a skull bomb that deals bonus damage and clears its neighbors.
- No valid moves left: the board reshuffles and both sides lose a small share of mana, so stalling isn't free.

**Skyfall.** New gems are drawn from a seeded queue that is fixed when the battle starts. The same queue feeds both sides and the AI cannot see further ahead than the player's preview. This makes replays deterministic, makes balance tests reproducible and answers the "the AI cheats" complaint directly.

## Combat and spells

A battle ends when one side hits 0 HP; on your turn you either swap gems, cast one spell, or swing your weapon, and some spells don't end your turn.

**Resources per side:** HP, four mana pools (each capped by stats), and action points from gauntlet gems. Every class equips a weapon and can swing it for a fixed action-point cost (a dagger is cheap and weak, a greatsword expensive and strong). Melee classes get more from it through cheaper swings and on-hit effects; casters mostly match gauntlets to deny them to the enemy. Giving everyone weapons, as PQ2 did, keeps every gem type worth matching for every class and keeps the AI's board evaluation the same across classes.

**Spells.** Each hero equips up to 6 spells, each with a mana cost and sometimes a cooldown. Every spell belongs to one of five families:

- **Damage:** direct hits, often scaled by gems on the board ("deal 2 damage per red gem").
- **Board shaping:** convert one color to another, destroy a row, column or color, swap gem positions.
- **Status:** apply effects from the table below.
- **Economy:** drain or steal enemy mana, gain gold, gain action points.
- **Tempo:** grant an extra turn, delay the enemy's next spell.

| Status | Effect | Typical source |
| --- | --- | --- |
| Stun | Skip next turn | Water, skull bombs |
| Burn | Damage each turn; red matches take longer to clear it | Fire |
| Poison | Damage each turn, stacking | Earth |
| Freeze | One mana color can't be gained | Water |
| Silence | Can't cast spells for N turns | Air |
| Barrier | Absorbs the next N damage | Earth |

**Anti-loop rule.** Extra turns from 4-matches always apply, but spell-granted extra turns can chain at most twice in a row. Stun can't be reapplied to a target that was just stunned. Late-game builds in the originals could lock enemies out entirely; this keeps combos strong without making fights non-interactive.

**Enemy AI.** Enemies use the same rules, board and skyfall queue as the player. Difficulty comes from search depth and how well the AI weighs what it leaves behind, not from hidden bonuses:

- Easy: best immediate match by reward.
- Normal: one-move lookahead, penalizes leaving 4-matches for the player.
- Hard: two-move lookahead within the visible queue, plans spell timing.

Bosses get unique spells and passives instead of stat padding.

## Hero progression

Four starting classes, each built around a different way of playing the board; names are placeholders.

| Class | Plays like | Primary gems | Signature mechanic |
| --- | --- | --- | --- |
| Warden | Tank, outlasts | Earth, skulls | Barriers that convert absorbed damage into green mana |
| Arcanist | Board control | Water, Air | Color conversion and gem locks |
| Reaver | Burst melee | Fire, action gems | Weapon swings that leave burning gems behind |
| Hexblade | Disruption | Air, Fire | Mana steal and silence |

**Stats.** One mastery stat per mana color (bonus mana per match and a chance for an extra turn on that color), plus Might (skull and weapon damage), Vitality (HP) and Cunning (who moves first, resist chance). Each level grants points; each class has cheaper and costlier stats, as in PQ1.

**Spells come from three places:** class level-ups (fixed list), captured monsters (see below), and rare drops. This is what keeps the 6 spell slots interesting late in the game.

**Equipment.** Six slots: weapon, armor, helm, shield, two trinkets. Gear should change rules, not just add stats; for example "Air matches also grant 1 action point" or "your first spell each battle costs 2 less". Sets of 3 give a set bonus.

Level cap 50 for the main campaign. Respec costs gold at the citadel, so experimenting with builds stays cheap.

## Puzzle variants and meta systems

Every non-combat interaction reuses the board engine with a different rule set and win condition, which is cheap to build once the engine exists and gives the game most of its variety.

| Activity | Board rule | Win condition | Reward | From |
| --- | --- | --- | --- | --- |
| Capture | Hand-built static board, no skyfall | Clear every gem | Learn a spell from that monster type | PQ1 |
| Forge | Rune and anvil gems | Collect the recipe's runes in N moves | Crafted item with chosen traits | PQ1 |
| Siege | Normal battle vs a garrison with bonuses | Win the battle | Town tribute (gold per day) | PQ1 |
| Lockpick | Gems must be matched in a shown color order | Finish the sequence before a wrong match | Chest contents | PQ2 |
| Bash door | Only skulls and Might count | Fill a meter in N moves | Shortcut or room access | PQ2 |
| Disarm trap | Skull matches hurt you | Collect N gauntlets without matching a skull | Avoid trap, keep loot | PQ2 |
| Search | Gold gems worth more | Collect N gold before the board runs dry | Hidden items | PQ2 |

**Capture is the centerpiece meta system.** Beating a monster type a few times unlocks its capture puzzle; solving it teaches you one of that monster's spells. This rewards exploring, and capture puzzles are fixed, hand-designed levels, so they double as a content pipeline for pure puzzle lovers.

**Citadel.** A home base you upgrade with gold, as in PQ1. Each building unlocks a system:

- Mage tower: spell research and respec.
- Dungeon: captured monsters, needed to research their spells.
- Forge: crafting.
- Stables: a mount that adds one small passive (move speed on the map, or +HP).
- Barracks: companion slots.

## World and structure

The campaign is dungeon-first, as in PQ2: most play happens room by room inside dungeons, with a light overworld that connects them.

- **Dungeons (the spine):** each act has 2–3 dungeons of 8–15 rooms laid out as a small graph with optional branches. Each room is one board encounter: fight, lockpick, trap, search, bash door or mini-boss. Cleared rooms stay cleared, shortcuts open as you go, and a cleared dungeon offers a fast exit, which avoids PQ2's backtracking.
- **Overworld:** a simple node map linking towns and dungeon entrances, with instant travel. A few roaming enemies on roads give optional fights.
- **Towns:** shops, quest givers and siege targets; the home town holds the citadel.
- **Quests:** a main quest in 6–8 acts and side quests per region. Quest types: clear a dungeon, defeat X, capture Y, recover an item, escort (fight with a fragile ally on your side).
- **Companions:** recruited through quests; each gives a passive and a once-per-battle triggered effect ("when you fall below 25% HP, gain 8 blue mana"). Only one active at a time.
- **Story and setting:** classic high fantasy (rival kingdoms, elves, dwarves, the undead, dragons), told through short dialogue panels with portraits. Original world, factions and names throughout.

Post-campaign: a challenge tower of escalating boss fights and a daily seeded board shared by all players, which the deterministic skyfall makes trivial to support.

## Tech and art direction

The most important technical decision is to build the rules engine as a pure, deterministic library separate from the game client.

- **Rules engine:** board state, match resolution, cascades, spells and status effects as pure functions over a seeded state. No rendering, no clocks. This lets the AI simulate moves cheaply, lets you run thousands of headless AI-vs-AI battles for balance, and makes bugs reproducible from a seed plus a move list.
- **Content as data:** spells, items, enemies, classes, rooms and capture puzzles defined in JSON or Godot resources with a small effect vocabulary (deal damage, convert gems, apply status, grant mana). New content should rarely need code.
- **Client:** Godot 4. Start the rules engine in GDScript; if AI lookahead or batch balance runs get slow, move just the engine to C# inside Godot. Balance runs use Godot's headless mode.
- **Platforms:** Windows and Linux first, which also covers Steam Deck; macOS later.
- **Steam later:** leave Steamworks (achievements, cloud saves) out of the MVP, but keep saves and settings in one place so adding it later is easy. GodotSteam is the usual integration.
- **Saves:** a single JSON save per slot; battles are not saved mid-fight in the MVP.

**Art.** 2D painted portraits for heroes and enemies, a hand-drawn overworld map, and a clean, high-contrast board. Each gem has a distinct shape as well as color so the game is colorblind-safe. Effects are short and punchy, with a 1×/2×/instant animation speed setting.

**Audio.** A small adaptive soundtrack (map, battle, boss) and satisfying cascade sounds that rise in pitch with chain length.

## Scope

The MVP proves one thing: that a single battle on the shared board is fun and fair, with enough progression around it to want the next one.

**MVP (vertical slice, one region)**

- Deterministic rules engine with all seven gem types, match rules, cascades and seeded skyfall
- Battle screen: player vs AI, with spells, status effects and weapon attacks
- Two classes (Warden, Arcanist), 12 spells each, levels 1–10
- AI at three difficulties, all using the same rules
- One town hub and two dungeons of 8–12 rooms each, 12 enemy types, 1 boss
- Room types: fight, lockpick, trap, search
- Capture puzzles for 6 enemy types
- Basic gear (weapon, armor, 2 trinkets) and a gold shop
- Headless AI-vs-AI balance runner

**Later**

- Remaining classes, levels 11–50, full gear slots and sets
- Citadel, forge, sieges, mounts, companions
- Remaining dungeons, overworld regions and the full main quest
- Challenge tower and daily seeded board
- Steam release prep: Steamworks, controller and Steam Deck polish, store page
- Mobile, only if the Steam release goes well

**Out of scope**

- Real-time or PvP multiplayer
- Gacha, energy timers or paid gems
- Procedurally generated story
- 3D art

## Risks and decisions

The biggest risk is balance: spell and gear combos that create unbeatable loops or make the board irrelevant.

**Risks**

- **Combo balance.** Mitigation: the anti-loop rule, plus the headless balance runner flagging any build whose win rate or average turns-per-fight is an outlier.
- **AI fairness perception.** Even a fair AI feels like it cheats after a bad cascade. Mitigation: the shared seeded queue, the drop preview, and a post-battle log of who got which cascades.
- **Content volume.** Spells, enemies and capture puzzles are the long pole. Mitigation: data-driven content and a small effect vocabulary.
- **Art cost.** Portraits for every enemy add up. Mitigation: reuse bodies with palette swaps for enemy tiers.
- **Too close to the source.** Mechanics like match-3 combat are shared across the genre, but names, setting, art and text must be original.

**Decisions (Oct 20, 2026)**

| Question | Decision |
| --- | --- |
| Audience | Personal project first; Steam release is a later goal |
| Engine | Godot 4 |
| Structure | Dungeon-first, like PQ2 |
| XP | Awarded only at battle end; no XP gem |
| Weapons and action gems | Every class uses them; melee classes get more out of them |
| Setting | Classic high fantasy, original names |
| Pricing | Not a concern now; one-time purchase if released |
