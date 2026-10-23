# Shardkeep — M1 Task List

Oct 23, 2026 · Draft

## Overview

M1 turns the M0 prototype into the MVP's battle game, as the [design doc](technical_design.md#m0-results) defines it: the two MVP classes (Warden and Arcanist) with 12 spells each, levels 1–10, the full status set and a playable Hard AI. It builds on the M0 engine, tools and tests; dungeons, room puzzles, capture, gear and the town come in later milestones.

**Scope calls in this draft** (change them before starting if they're wrong):

- M1 includes a small enemy roster and a fight-select screen. Levels need XP and XP needs enemies, but dungeons stay out of M1.
- Hard ships only if it fits its budget on the slowest target machine. M0 skipped that measurement, so T8 has to do it.
- The fun check M0 skipped becomes T10, a lighter version.

A task is done when every acceptance box is ticked and CI is green.

**Order.** T1 comes first. T2 and T3 can then go in either order. T4 needs T3, and T5 needs T2–T4. T6 and T7 need T5 and can go in either order. T8 can start after T4. T9 needs T5–T8, and T10 comes last.

## T1 · Stats and who moves first

Add the stat block from the product brief to both sides, and let it drive the numbers that M0 hard-coded.

- `Stats` on `SideState`: one mastery per mana color, plus Might, Vitality and Cunning. All are content-driven and included in the state hash.
- **Vitality** sets max HP. **Might** adds flat damage to skull matches, skull bombs and weapon swings.
- **Mastery** gives bonus mana per match of its color, plus a chance of an extra turn on that color. The roll comes from the `effects` stream.
- **Who moves first:** higher Cunning goes first, with ties broken by the `setup` stream. `second_mover_mana` goes to whichever side moves second, not always side 1.
- **Cunning's resist chance** against statuses (stun, freeze, silence, poison), rolled from the `effects` stream.
- AI search: mastery and resist rolls are hidden information, so simulated states use expected values and never read those rolls.

**Acceptance criteria**

- [ ] Golden-board tests for Might on skulls, bombs and weapons, and for mastery's bonus mana
- [ ] With equal Cunning, who moves first follows the seed; with higher Cunning, that side always moves first
- [ ] The M0 fog test still passes with mastery and resist rolls in play (hidden rolls never change the AI's decision)
- [ ] The replay fixtures are re-recorded on purpose (`tools/replay.gd --write`), with the diff explained in the PR

## T2 · Full status set

Finish the status table: burn's red-match rule, poison, freeze and silence, plus the `on_gain` hook.

- **Poison** stacks: damage each turn equal to its stacks.
- **Burn**'s rule from the brief: red matches clear it faster.
- **Freeze** names one mana color the side can't gain. This needs the new `on_gain(owner, resource, amount)` hook.
- **Silence:** no spell casting for N turns. `legal_actions` and the spell bar both respect it.
- `statuses.json` and its schema grow to cover these. The AI's status value scores each one.
- The battle screen shows each status's turns and stacks.

**Acceptance criteria**

- [ ] One golden test per status, plus tests that each hook (`on_turn_start`, `on_gain`, `on_damage_taken`, `on_turn_end`) runs in its documented order
- [ ] A frozen color gains nothing from matches, blasts or spells, and the event stream says so
- [ ] Silence removes every `Cast` from `legal_actions` and disables the spell buttons
- [ ] The fuzz run includes spells that apply each status and still passes 10,000 actions

## T3 · Remaining effect ops

Implement the rest of the MVP effect vocabulary, so the 24 class spells can be written as data.

- `heal`, `drain_mana`, `steal_mana`, `gain_ap`
- `destroy` by row, column, color or area, with the `collect` flag deciding whether destroyed gems pay out
- `lock_gems` (count, turns): uses `Board.locked`. Locked gems can't be swapped, and locks tick down at turn end.
- A tempo op that delays the enemy's next spell (raises its cooldowns)
- Each op goes into `effect.schema.json`, `EffectRunner.OPS` and the content lint

**Acceptance criteria**

- [ ] A golden-board test for each op, including `destroy` with and without `collect`
- [ ] Locked gems never appear in a legal swap, and locks expire on time
- [ ] `steal_mana` respects both sides' caps and freeze
- [ ] An unknown op or a missing parameter fails the schema check in CI

## T4 · Targeted spells

Let spells pick a row, column, cell or color, so board-shaping spells are real choices.

- `Action.cast(spell, target)`, with a target kind declared per effect in content
- `legal_actions` lists each valid target. The AI searches them, capped per spell so branching stays bounded.
- Battle screen: click a targeted spell, see the valid targets highlighted, click one to cast, and right-click or Esc to cancel
- Replays and fuzz record targets

**Acceptance criteria**

- [ ] Every target `legal_actions` offers is accepted by `apply()`, and nothing else is
- [ ] Normal and Hard pick the best target on a golden board where one row is clearly best
- [ ] Targeted casts round-trip through replay files and the F9 export
- [ ] Playable with the mouse only, including cancel

## T5 · Warden and Arcanist

Build the two MVP classes as data: stats, stat costs, a weapon and 12 spells each that unlock over levels 1–10.

- `classes.json` gains starting stats, per-stat point costs (cheap and costly stats, as in PQ1) and spell unlock levels
- **Warden** (Earth and skulls, tank): barriers that turn absorbed damage into green mana. This needs a status hook that grants a resource.
- **Arcanist** (Water and Air, board control): color conversion and gem locks
- 24 spells across the five families (damage, board shaping, status, economy, tempo)
- The content lint checks: 12 spells per class, unlock levels from 1 to 10, every referenced op, status and spell exists
- The M0 placeholder loadouts are retired (tests keep their own fixtures)

**Acceptance criteria**

- [ ] Each class's signature mechanic has a golden test (Warden's barrier pays green mana; Arcanist's locks block swaps)
- [ ] Every spell casts without errors in the fuzz run, for both classes at levels 1, 5 and 10
- [ ] Spell names, costs and effects show correctly on the spell bar

## T6 · Levels 1–10 and the hero

Give the player a hero that persists between battles, earns XP and levels up.

- `HeroState`, outside the battle state: class, level, XP, allocated stat points and up to 6 equipped spells. It builds the battle loadout.
- XP is awarded at battle end, scaled by the enemy's level, using a level curve in content
- **Level-up screen:** spend stat points at the class's costs, and equip unlocked spells into 6 slots
- Save and load at `user://hero.json`, versioned so later milestones can migrate it

**Acceptance criteria**

- [ ] Winning a fight grants the right XP; crossing a threshold levels up, grants points and unlocks that level's spells
- [ ] Stat spending respects class costs and can't go below the starting stats
- [ ] Quitting and relaunching restores the hero exactly
- [ ] A corrupt or older save is reported, not silently reset

## T7 · Enemies and fight select

Add something to level up against before dungeons exist.

- `enemies.json`, per the design doc's enemy schema: level, HP, mana caps, stats, spells, weapon, AI level and weights, XP and gold. About 6 enemies across levels 1–10.
- Fight-select screen: pick an enemy, see its level and spells, fight, then return
- Balance runner and fuzz accept enemy ids as loadouts

**Acceptance criteria**

- [ ] The content lint checks every enemy's spells, weapon, statuses and AI level
- [ ] A level 1 hero can beat the level 1 enemy on Easy
- [ ] The balance runner plays hero builds against enemies

## T8 · Playable Hard AI

Make Hard a real difficulty, inside its speed budget on the slowest target machine.

- `benchmark.gd` gains `--budget` (in ms), which exits 1 if Hard's average or 95th-percentile decision time is over
- Measure on the slowest target (Steam Deck), then set `AI.BEAM` from the data. M0's sandbox numbers were 316 ms at beam 6, 171 at 4 and 101 at 3. If no beam that plays well fits, port the engine to C#.
- Hard handles targets and the new statuses, and appears on the difficulty picker
- Results recorded in the design doc's speed table

**Acceptance criteria**

- [ ] Hard's average decision time is under 250 ms on the slowest target, recorded in the design doc
- [ ] In Normal-vs-Hard balance runs with the same class, Hard wins at least 60%
- [ ] The fog, lethal-swap and no-mutation tests cover Hard
- [ ] The battle screen stays responsive while Hard thinks (no frame over 50 ms)

## T9 · Balance pass

Tune the classes and enemies with the balance runner, and close the flags M0 left open.

- Balance-runner presets for hero builds at levels 1, 5 and 10
- Re-check the first-mover rate under the Cunning rule. Keep, tune or drop `second_mover_mana`.
- Decide what to do about extra-turn chains above 6 (a cap for match extra turns, or a different match rule) and long battles

**Acceptance criteria**

- [ ] At Normal, Warden vs Arcanist wins fall between 40% and 60% at levels 1, 5 and 10
- [ ] Mirror matches stay within 45–55%, with the first mover at most 55%
- [ ] Average battle length is 15–40 turns, and no extra-turn chain is longer than 6, unless the design doc records a rule change
- [ ] Results recorded in the design doc

## T10 · Playtest and M1 exit

A short playtest across both classes before moving on, standing in for the fun check M0 skipped.

- At least 10 battles across both classes and all three difficulties, with notes saved from the win and loss screen
- The 3 most common complaints, and whether to fix them before M2

**Acceptance criteria**

- [ ] Notes recorded in `docs/fun_check.md`
- [ ] M1 results and the exit decision recorded in the design doc
