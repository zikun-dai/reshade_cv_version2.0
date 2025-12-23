# AGENTS.md

## Dev environment tips
- Project layout: `gcv_games/` (game classes), `gcv_reshade/` (pipeline core), `gcv_utils/` (shared structs and memory read helpers), `mod_scripts/` (game scripts, not part of build), `python_threedee/` (post-process scripts, not part of build).
- Useful references: `gcv_utils/camera_data_struct.cpp` for data layouts and `gcv_utils/memread.cpp` for memory read helpers.
- Most work happens in `gcv_games/` and `gcv_reshade/`; other folders are usually peripheral.

## Testing instructions
- Check `.github/workflows` if CI exists for this repo.
- If you add or change logic, run the repo's existing test or validation steps (if any).
- After edits to memory offsets or camera matrices, validate in-game behavior before merging.

## PR instructions
- Provide a concise title describing the game/module and change.
- Note any in-game validation performed.
