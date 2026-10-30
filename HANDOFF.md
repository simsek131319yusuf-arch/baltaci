# HANDOFF — Baltacı (2026-10-30)

Cozy incremental tree-cutting game. Godot **4.7.2**, GDScript, 2D, GL Compatibility, 1600×900 (`stretch aspect = keep`).
Mascot **Pipsy** (yellow puppy; the owner's friend's character, used with permission). UI text is Turkish; code identifiers English.
Talk to the owner (Yusuf) in Turkish.

## Read first
1. `CONTRACT.md`: architecture, autoload API, gameplay rules, art ids. Binding.
2. `data/*.json`: all balance numbers (trees, upgrades, balance + juice, story).
3. `scenes/story/INTEGRATION.md`: story hook points.

## Layout
- `scripts/autoload/`: `Balance` (data), `Art` (sprite lookup with fallback), `GameState` (gold/levels/flags/save, `save_path` + `persist` overrides for tests), `Story` (beats, dialogue overlay).
- `scenes/camp/`: hub, upgrades bench (main scene).
- `scenes/forest/`: the run: endless forest, auto-swinging axe, **felling chain** (signature mechanic), HUD, results, juice/fx.
- `scenes/story/`: dialogue box, toast, letter, demo scene.
- `scenes/ui/`: theme, number formatting, juice helpers, iris scene transition, coin burst.
- `art/sprites/`: 38 RGBA sprites (manifest in `art/manifest.json`). `art/raw/` keeps only Pipsy references; raw generations are gitignored.
- `tests/`: headless tests; `tools/sim_balance.gd`: perfect-aim balance simulator.

## Commands
```
godot --headless --path . --import            # first time (creates .godot/)
godot --headless --path . -s tests/run_all.gd # all tests; must be green
godot --path . res://scenes/forest/forest.tscn -- --autoshot=/abs/out.png   # needs a display
```
On the cloud VM: download the Linux build of Godot 4.7.2 (standard, not .NET) and use `--headless`. Screenshot modes need a display; try `xvfb-run` if available, otherwise skip visual checks and say so.

Status at handoff: `run_all` **6/6 PASS** (smoke, economy, economy_fmt, forest, juice, story).

## Rules
- Tests must never write the real save. Use `GameState.save_path` override / `GameState.persist = false`, and `Story.ui_enabled = false` in tests.
- Never derive keys/filenames with `to_lower()` (Turkish-I bug). Use fixed ASCII keys.
- Numbers belong in `data/*.json`, not code.
- Missing art must never crash (`Art.tex()` returns null, so draw a placeholder).
- Write tests with expected values computed by hand in advance.

## Open work (the integration pass was stopped midway; verify each)
1. **Story hooks**: already present in `camp.gd` (`camp_enter`) and `forest.gd` (`depth`, `tree_first_seen`, `chain`, `run_end`). Verify against INTEGRATION.md:
   - the run_end dialog opens after the results reveal and blocks "Kampa Dön" while open;
   - camp_enter plays after the scene transition;
   - autoplay/autoshot never triggers blocking story.
2. **Map piece card**: support an optional line field `"show": "story/map_piece"` in `data/story.json`, rendered by `scenes/story/dialogue_box.gd` as a pop-in image card above the box. Use it in the Kemal reward beat and the depth-100 finale.
3. **Polish**:
   - (a) Camp purchase coins should fly from the gold counter to the bought card.
   - (b) The camp backdrop's `bg/mid` should be scaled down and hazed like the forest.
   - (c) Tree ground shadows should be neutral dark at low alpha, not green.
   - (d) Pipsy's result reaction should be relative to the player's own history (an EMA in a GameState flag), not the absolute 60/20 gold.
   - (e) Cap log/dust/leaf clutter in long chains.
   Some of these may be partially done; check the code.
4. Add tests for 2 and 3(d). Keep `run_all` green.

## Later roadmap (see the design doc in the owner's vault, `Oduncu-GDD.md`)
Week 2: skill tree + XP/levels. Week 3: sawmill (hızar) + order board + nursery (fidanlık) + helpers + offline progress (8 h cap). Week 4: special objects (lightning tree, beehive, bird nest, rotten stump, rock, mushroom ring) + Steam (GodotSteam). Week 5: Steam page + demo. The game's name is undecided.

New art is generated with Nano Banana on the owner's PC (not available in the cloud). If an asset is missing, use a placeholder and list it in your report.
