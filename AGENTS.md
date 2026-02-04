# Repository Guidelines

## Project Structure & Module Organization
- `gcv_reshade/`: ReShade addon core (capture, recording, shader integration).
- `gcv_games/`: per-game implementations (`GameName.cpp/.h`) and factory registration.
- `gcv_utils/`: shared structs and memory read helpers.
- `reshade_shaders/`: custom `.fx` effects.
- `mod_scripts/`: game mods for camera data (not built).
- `python_threedee/`: post-processing tools (not built).
- `build/`: build outputs; solution file is `gcv_reshade.sln`.
- Useful references: `gcv_utils/camera_data_struct.cpp`, `gcv_utils/memread.cpp`.

## Build, Test, and Development Commands
- `start gcv_reshade.sln` opens the solution in Visual Studio 2022.
- `msbuild gcv_reshade.sln /p:Configuration=Release /p:Platform=x64` builds `cv_captures.addon` to `build/x64/Release/` (Debug goes to `build/x64/Debug/`).
- vcpkg target `x64-windows` dependencies: `eigen3`, `nlohmann-json`, `xxhash`. Example: `vcpkg install eigen3 nlohmann-json xxhash --triplet x64-windows`.
- ReShade source is expected at `..\\reshade-5.8.0` (sibling to this repo).

## Coding Style & Naming Conventions
- C++ uses 4-space indentation and braces on the same line. Follow existing formatting; avoid mass reformatting.
- Naming: classes/types in `PascalCase`, functions and locals in `snake_case`. Game files use `GameName.cpp/.h`.
- Python scripts use 4-space indentation and `snake_case`.

## Testing Guidelines
- No automated test suite or CI currently.
- Validate in-game behavior for any logic change, especially memory offsets, camera matrices, and depth conversions. Record game name, API, and version with a sample capture.
- For data pipeline checks, run relevant scripts in `python_threedee/` and verify outputs visually.

## Commit & Pull Request Guidelines
- Git history favors short, descriptive messages (often Chinese) and sometimes includes the game/module name; keep commits concise and focused.
- Use feature branches like `wip/<game>-<feature>` and merge back to `main` after verification (see `BUILD.md` for the exact workflow).
- PRs: title should state game/module plus change. In the description, note in-game validation steps/results and any new scripts or offsets.
