# Baltacı 🪓🐶

Cozy 2D incremental tree-cutting game made with **Godot 4.7.2 (GDScript)**. You play **Pipsy**, a yellow
puppy who arrives at grandpa Bodo's abandoned lumber camp. Shifts are short and timed. The axe swings on
its own, and a felled tree knocks over the ones in its path, so chains build up like dominoes. You spend
the gold at the camp on upgrades, and a light story unfolds between shifts.

> Status: week‑1 vertical slice (playable). The game's final name is undecided. UI text is in Turkish.

## Features
- **Felling chain:** a tree falls away from the side you hit it from and damages trees in its fall range by its height. Chains are capped at a +100% bonus.
- **Endless forest:** columns get denser and more valuable (poplar → pine → spruce) the deeper you go.
- **Camp:** a five-slot upgrade bench. Costs are tuned with a balance simulator so everything is maxed in about 30 shifts.
- **Story ("Dedenin Kampı"):** dialogue with portraits and a typewriter effect. Characters are Bilge Baykuş (the wise owl) and Kunduz Kemal (the rival beaver), plus grandpa's letters.
- **Juice:** wind-up and hit-stop on the axe, spring wobble on hit, a gravity fall with bounces, particles, trauma-based screen shake, and iris scene transitions.
- **Save system:** versioned saves with a backup and recovery from corrupted files.

## Run
1. Install [Godot 4.7.2](https://godotengine.org/) (the standard build, not .NET).
2. Open `project.godot` in Godot, or run `godot --path .`

To run the tests headless, use `godot --headless --path . -s tests/run_all.gd`. A screenshot mode is also available: `godot --path . res://scenes/forest/forest.tscn -- --autoshot=/abs/shot.png`

## Repository map
| Path | What |
|---|---|
| `scripts/autoload/` | `Balance` (data), `Art` (sprite lookup with fallback), `GameState` (save), `Story` |
| `scenes/forest/`, `scenes/camp/`, `scenes/story/`, `scenes/ui/` | gameplay, hub, dialogue, shared UI and juice |
| `data/*.json` | all balance numbers, upgrades, story beats |
| `tests/`, `tools/sim_balance.gd` | headless tests, balance simulator |
| `art/` | sprites + generation tools (see license below) |
| `CONTRACT.md`, `HANDOFF.md` | architecture contract and current handoff notes |
| `docs/GELISTIRME-NOTLARI.md` | how it was built: phases, tools, AI agents, lessons (Turkish) |

## License
- **Code:** MIT ([LICENSE](LICENSE)).
- **Art and the Pipsy character:** **not** covered by MIT, all rights reserved ([art/LICENSE.md](art/LICENSE.md)). Pipsy is a friend's character, used with permission.
