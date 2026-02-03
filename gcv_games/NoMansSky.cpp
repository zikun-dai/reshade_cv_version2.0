// Copyright (C) 2022 Jason Bunk
#include "NoMansSky.h"
#include "gcv_utils/memread.h"
#include <cstdint>
#include <cmath>
#include <reshade.hpp>
#include <cstdio>
#include <cstring>

std::string GameNoMansSky::gamename_verbose() const { return "NoMansSky_Vulkan"; }

std::string GameNoMansSky::camera_dll_name() const { return ""; } // use main exe memory space
uint64_t GameNoMansSky::camera_dll_mem_start() const { return 0x68F9280ull; }
GameCamDLLMatrixType GameNoMansSky::camera_dll_matrix_format() const { return GameCamDLLMatrix_4x4; } // not used, we override get_camera_matrix

bool GameNoMansSky::can_interpret_depth_buffer() const {
	// Depth conversion is approximate - near/far plane values may need calibration
	return true;
}

// No Man's Sky uses Vulkan with reversed-Z depth buffer
// Raw depth: 1.0 = near plane, 0.0 = far plane
// These near/far values are approximate and may need adjustment
#define NMS_NEAR_PLANE 0.1f
#define NMS_FAR_PLANE 50000.0f

float GameNoMansSky::convert_to_physical_distance_depth_u64(uint64_t depthval) const {
	// Interpret raw bits as float (32-bit float depth buffer)
	uint32_t depth_as_u32 = static_cast<uint32_t>(depthval);
	float raw_depth;
	std::memcpy(&raw_depth, &depth_as_u32, sizeof(float));

	// Reversed-Z: near plane = 1.0, far plane = 0.0
	// For reversed-Z with infinite far plane: physical_depth = near / raw_depth
	// For reversed-Z with finite far plane, we use the standard formula with (1 - depth)

	// Clamp to avoid division by zero
	if (raw_depth <= 0.0001f) {
		return NMS_FAR_PLANE;
	}

	// Reversed-Z infinite far plane formula (simpler and often more accurate for Vulkan games)
	// physical_distance = near_plane / raw_depth
	return NMS_NEAR_PLANE / raw_depth;
}

bool GameNoMansSky::get_camera_matrix(CamMatrixData& rcam, std::string& errstr) {
	rcam.extrinsic_status = CamMatrix_Uninitialized;
	if (!init_in_game()) return false;

	const UINT_PTR dll_base = (UINT_PTR)camera_dll;
	SIZE_T nbytesread = 0;

	// Read 4x4 matrix from NMS.exe+68F9280
	// Matrix layout in memory (row-major):
	// mat[0][0..3] = row 0: rotation col 0 (x-axis), 0
	// mat[1][0..3] = row 1: rotation col 1 (y-axis), 0
	// mat[2][0..3] = row 2: rotation col 2 (z-axis), unknown value (ignored)
	// mat[3][0..3] = row 3: translation (x,y,z), proj11 (for fov calculation)
	float mat4x4[16] = {};
	const uint64_t cam_matrix_offset = camera_dll_mem_start();

	if (!tryreadmemory(gamename_verbose() + std::string("_4x4cam"), errstr, mygame_handle_exe,
		(LPCVOID)(dll_base + cam_matrix_offset), reinterpret_cast<LPVOID>(mat4x4),
		sizeof(mat4x4), &nbytesread)) {
		return false;
	}

	// mat4x4 is stored row-major: mat4x4[row*4 + col]
	// The first 3 columns of the first 3 rows form a rotation matrix
	// We need to transpose it to get the c2w rotation
	// Translation is in row 3, cols 0-2

	// Extract and transpose the 3x3 rotation to get c2w rotation
	// Original: columns are in rows, so transpose means: c2w(i,j) = mat[j][i]
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			rcam.extrinsic_cam2world(i, j) = mat4x4[j * 4 + i];
		}
	}

	// Translation is in row 3, columns 0-2: mat4x4[3*4+0], mat4x4[3*4+1], mat4x4[3*4+2]
	rcam.extrinsic_cam2world(0, 3) = mat4x4[12]; // mat[3][0]
	rcam.extrinsic_cam2world(1, 3) = mat4x4[13]; // mat[3][1]
	rcam.extrinsic_cam2world(2, 3) = mat4x4[14]; // mat[3][2]

	rcam.extrinsic_status = CamMatrix_AllGood;

	// mat[3][3] appears to be proj[1][1] = cot(fov_v/2)
	// fov_v = 2 * atan(1 / proj11)
	float proj11 = mat4x4[15]; // mat[3][3]
	if (proj11 > 0.1f && proj11 < 10.0f) {
		rcam.fov_v_degrees = static_cast<float>(2.0 * std::atan(1.0 / static_cast<double>(proj11)) * (180.0 / 3.14159265358979323846));
	}

	// Note: mat[2][3] (mat4x4[11]) contains an unknown value (~-0.43), ignored for now

	return true;
}
