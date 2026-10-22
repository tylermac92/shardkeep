# shardkeep

A match-3 RPG in Godot 4.7. Design docs live in [`docs/`](docs/).

## Layout

| Folder | What lives there |
| --- | --- |
| `engine/` | Pure, deterministic rules. No nodes, clocks, global RNG, autoloads or `client/` code (enforced by `tools/lint_engine.sh`) |
| `content/` | JSON data, one file per type |
| `schemas/` | JSON Schema for each `content/<name>.json`, as `<name>.schema.json` |
| `client/` | Scenes and UI |
| `autoload/` | `ContentDB` and other singletons |
| `tools/` | Headless scripts and CI lints |
| `tests/` | GUT tests (`test_*.gd`) |
| `addons/gut/` | Vendored [GUT](https://github.com/bitwes/Gut) 9.7.1 |

## Play

`godot` from the project folder opens the battle screen (M0: placeholder art). Pick Easy or
Normal, then swap gems by clicking two neighbors or dragging one onto the other. The seed is
shown at the top; 1x, 2x and Instant set the animation speed.

## Checks

Run what CI runs:

```sh
godot --headless --import                              # once, after a fresh clone
tools/run_tests.sh                                     # GUT tests (fails if a test script fails to load)
godot --headless --script res://tools/content_lint.gd  # content reference checks
tools/validate_content.sh                              # JSON Schema (pipx install check-jsonschema)
tools/lint_engine.sh                                   # engine purity lint
tools/test_lints.sh                                    # proves the two lints above catch bad input
godot --headless --script res://tools/benchmark.gd -- --positions 200  # AI decision time per level
```
