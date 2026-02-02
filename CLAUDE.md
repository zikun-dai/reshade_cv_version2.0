# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a ReShade addon that extracts training data from games for deep neural networks (DNN), including RGB images, depth maps, camera matrices, and semantic segmentation. It supports creating datasets for NeRF reconstruction, SLAM, monocular depth estimation, and semantic segmentation.

The addon hooks into game rendering pipelines via ReShade 5.8.0+ to capture:
- RGB frames
- Depth buffers (calibrated physical distance when supported)
- Camera extrinsic matrices (cam2world) and FOV
- Semantic segmentation data (DirectX 10/11 only)

## Build Commands

### Build with Visual Studio
```bash
# Open solution in Visual Studio 2022
start gcv_reshade.sln

# Or build from command line with MSBuild
msbuild gcv_reshade.sln /p:Configuration=Release /p:Platform=x64
```

The build outputs `cv_captures.addon` to `build/x64/Debug/` or `build/x64/Release/`.

### Dependencies via vcpkg

Required vcpkg packages (target `x64-windows`):
- `eigen3` - Matrix operations
- `nlohmann-json` - JSON serialization
- `xxhash` - Fast hashing

ReShade 5.8.0 source must be placed at `..\reshade-5.8.0` (one level up from this repo).

### Installation to Game

1. Install ReShade 6.4.0+ to your game directory
2. Copy the compiled `cv_captures.addon` to the game executable directory (where `ReShade.log` is)
3. For games requiring camera matrix extraction, install the appropriate mod script from `mod_scripts/` (see game-specific instructions in script comments)
4. Copy `reshade_shaders/*.fx` to the ReShade shader search path if needed

## Architecture

### High-Level Data Flow

1. **Game Rendering** → ReShade hooks intercept draw calls and frame buffers
2. **ReShade Addon (gcv_reshade)** → Captures RGB, depth, and camera data each frame
3. **Game Interface (gcv_games)** → Game-specific logic extracts camera matrix and converts depth values
4. **Writer Threads** → Serialize data to disk asynchronously (JSON + NPY + FPZIP compressed depth)
5. **Post-processing (python_threedee)** → Convert captures to NeRF transforms.json or point clouds

### Core Components

**`gcv_reshade/` - ReShade Addon Core**
- `main.cpp`: Main addon entry point with ReShade API hooks. Handles F11 (single capture) and F9/F10 (video recording start/stop) hotkeys.
- `copy_texture_into_packedbuf.cpp/.h`: Texture copying utilities for RGB and depth buffers. Supports shader-based depth capture for DX12/Vulkan via `DepthCapture.fx`.
- `grabbers.cpp/.h`: Frame buffer grabbing logic
- `recorder.cpp/.h`: Video recording state machine
- `image_writer_thread_pool.cpp/.h`: Async disk I/O for captured frames

**`gcv_games/` - Game-Specific Implementations**
- Each game has its own class (e.g., `Cyberpunk2077.cpp`, `ResidentEvils.cpp`, `HorizonZeroDawn.cpp`)
- Game classes must implement:
  - `gamename_verbose()`: Display name
  - `camera_dll_name()` / `camera_dll_mem_start()`: Where to find camera data in memory
  - `convert_to_physical_distance_depth_u64()`: Convert raw depth buffer values to meters
  - Camera matrix extraction logic (often via scripted buffer or memory scanning)
- `game_interface_factory.cpp`: Factory pattern for auto-registering game implementations

**`gcv_utils/` - Shared Utilities**
- `camera_data_struct.cpp/.h`: `CamMatrixData` struct for extrinsic matrices and FOV, serialization to JSON
- `memread.cpp/.h`: Memory reading helpers for extracting data from game process memory
- `depth_utils.h`: Depth conversion utilities
- `scripted_cam_buf_templates.h`: Templates for extracting camera data from script-injected memory buffers

**`mod_scripts/` - Game Mod Scripts** (not part of C++ build)
- Lua/CET scripts that run inside games to export camera matrices to shared memory
- Examples: `cyberpunk2077_cyberenginetweaks_mod_init.lua`, `residentevil_read_camera_matrix_transfcoords.lua`

**`python_threedee/` - Post-Processing Scripts** (not part of C++ build)
- `convert_game_snapshot_jsons_to_nerf_transformsjson.py`: Aggregate per-frame JSONs into NeRF-ready transforms.json
- `load_point_cloud.py`: Visualize captures as 3D point clouds in Open3D, save as PLY/PCD
- `_jake/run_pipeline.py`: Full pipeline to reconstruct point clouds from captured data

**`reshade_shaders/` - Custom ReShade Effects**
- `DepthCapture.fx`: Shader for capturing depth on DX12/Vulkan where direct buffer access isn't available
- `segmentation_visualization.fx`: Real-time visualization of semantic segmentation
- `displaycamcoords.fx`: Display camera coordinates overlay

### Depth Capture Strategies

The addon supports two depth capture methods:

1. **Direct Buffer Access** (DX10/DX11/some DX12): Read depth/stencil buffer directly from GPU memory
2. **Shader-Based Capture** (DX12/Vulkan fallback): `DepthCapture.fx` renders ReShade's depth buffer to a texture that the addon can read

The code in `gcv_reshade/main.cpp` (lines 40-85) handles automatic fallback to shader-based capture when direct access fails.

### Camera Matrix Extraction

Games use different methods to expose camera data:

- **Scripted Buffer**: Mod injects camera matrix into a known memory location (e.g., Cyberpunk 2077 via CyberEngineTweaks)
- **Memory Scanning**: Search process memory for camera matrix patterns (less reliable, game version dependent)
- **IGCS Connector**: Interface with IGCS camera tools (used by some Resident Evil games)

Game classes specify the extraction method via `camera_dll_matrix_format()` return value.

### Semantic Segmentation (DX10/DX11 only)

Uses RenderDoc code (`renderdoc/`) to intercept draw calls and assign mesh/shader IDs to semantic categories. Mapping mesh IDs to semantic labels is manual per-game effort.

## Workflow: Adding a New Game

1. Create `gcv_games/NewGame.cpp` and `gcv_games/NewGame.h` based on a similar game
2. Implement required `GameInterface` virtual methods:
   - Camera data extraction logic
   - Depth conversion formula (if known)
3. Register the game class with `REGISTER_TYPE` macro at bottom of .cpp
4. If needed, create a mod script in `mod_scripts/` to export camera matrix
5. Add the .cpp/.h to `gcv_reshade/gcv_reshade.vcxproj` and `.vcxproj.filters`
6. Build and test in-game

See `gcv_games/Cyberpunk2077.cpp` for a well-documented example using scripted camera buffer.

## Git Workflow (from BUILD.md)

**Main branch**: Verified, working commits only

**Feature branches**: For testing new features or games
```bash
git switch -c wip/gamename-feature
# Work and commit...
```

**Merge back to main**:
```bash
git switch main
git pull --rebase origin main
git merge --no-ff wip/gamename-feature
git push origin main
```

**Temporary testing** (detached HEAD):
```bash
git switch --detach <commit-hash>
# Test...
git switch main  # Discard changes and return
```

## Usage In-Game

- **F11**: Capture single frame (RGB + depth + JSON metadata)
- **F9**: Start video recording mode
- **F10**: Stop video recording mode

Captured data goes to `cv_saved/` directory with structure:
```
cv_saved/
  <timestamp>/
    00000_meta.json      # Camera matrix, FOV, resolution
    00000_depth.fpz      # FPZIP compressed depth (or .npy)
    00000.jpg            # RGB frame (from video extraction)
```

## Python Post-Processing

After capturing frames:

1. Extract video to individual JPG frames with ffmpeg
2. Run `python_threedee/convert_game_snapshot_jsons_to_nerf_transformsjson.py` to create transforms.json
3. Or run `python_threedee/load_point_cloud.py` to visualize as 3D point cloud

## Important File Formats

- **JSON metadata**: Contains `extrinsic_cam2world` (4x4 matrix), `fov_v_degrees`, `fov_h_degrees`, image dimensions
- **Depth format**: Either `.fpz` (FPZIP lossless float compression) or `.npy` (NumPy array). Values are in meters when `can_interpret_depth_buffer()` returns true for that game.
- **Semantic segmentation**: `.png` with pixel values representing semantic class IDs

## Notes

- Not all games support all features. Check README.md compatibility tables.
- Depth buffer interpretation requires per-game calibration (see `convert_to_physical_distance_depth_u64()` implementations).
- Camera matrix extraction requires game-specific reverse engineering or mod support.
- For new game support, start with depth-only capture (works for most ReShade-compatible games), then add camera matrix support if needed.
