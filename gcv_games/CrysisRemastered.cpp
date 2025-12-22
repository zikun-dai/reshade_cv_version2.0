// Copyright (C) 2022 Jason Bunk
#include "CrysisRemastered.h"
#include "gcv_utils/memread.h"
#include <cstdint>
#include <cmath>
#include <reshade.hpp>
#include <cstdio>

static uint64_t g_crysis_translation_log_counter = 0;
static int g_crysis_translation_log_interval_frames = 3;

std::string GameCrysis::gamename_verbose() const { return "Crysis2008_GOG_DX10_x64"; } // tested for this build

std::string GameCrysis::camera_dll_name() const { return ""; }
uint64_t GameCrysis::camera_dll_mem_start() const { return 0x23FB2BCull; } //unused, assign offset before reading
GameCamDLLMatrixType GameCrysis::camera_dll_matrix_format() const { return GameCamDLLMatrix_3x4; }

bool GameCrysis::can_interpret_depth_buffer() const {
	return true;
}

#define NEAR_PLANE_DISTANCE 0.25

// need to scan far plane in memory because it seems to change per level? 
#define FAR_PLANE_DISTANCE 13000.0
static float g_far_plane_distance = FAR_PLANE_DISTANCE;

float GameCrysis::convert_to_physical_distance_depth_u64(uint64_t depthval) const {
	const float far_plane_distance = g_far_plane_distance;
	
	// convert to physical distance
	uint32_t depth_as_u32 = static_cast<uint32_t>(depthval);
    float depth;
    std::memcpy(&depth, &depth_as_u32, sizeof(float));

    const float n = NEAR_PLANE_DISTANCE;
    const float f = far_plane_distance;
    const float numerator_constant = (-f * n) / (n - f);
    const float denominator_constant = n / (n - f);
    return numerator_constant / (depth - denominator_constant);
}

bool GameCrysis::get_camera_matrix(CamMatrixData& rcam, std::string& errstr) {
	rcam.extrinsic_status = CamMatrix_Uninitialized;
	if (!init_in_game()) return false;

	const UINT_PTR dll_base = (UINT_PTR)camera_dll;
	SIZE_T nbytesread = 0;

	float cambuf[12] = {};
	const uint64_t cam_matrix_offset = 0x23FB2B0ull;
	if (!tryreadmemory(gamename_verbose() + std::string("_3x4cam"), errstr, mygame_handle_exe,
		(LPCVOID)(dll_base + cam_matrix_offset), reinterpret_cast<LPVOID>(cambuf),
		sizeof(cambuf), &nbytesread)) {
		return false;
	}
	for (int row = 0; row < 3; ++row) {
		const int base = row * 4;
		const float old_col1 = cambuf[base + 1];
		cambuf[base + 1] = cambuf[base + 2];
		cambuf[base + 2] = -old_col1;
	}

	rcam.extrinsic_cam2world = cam_matrix_from_flattened_row_major_buffer(cambuf);
	
	//CamMatrix& M = rcam.extrinsic_cam2world;
	//M.col(1) = -M.col(1);// negate 2nd column (after swap)

	rcam.extrinsic_status = CamMatrix_AllGood;

	// read fov
	const uint64_t proj11_offset = 0x7D68FF4ull;
	float proj11 = 0.0f;
	if (!tryreadmemory(gamename_verbose() + std::string("_proj11"), errstr, mygame_handle_exe,
		(LPCVOID)(dll_base + proj11_offset), reinterpret_cast<LPVOID>(&proj11),
		sizeof(proj11), &nbytesread)) {
		return false;
	}
	rcam.fov_v_degrees = static_cast<float>(2.0 * std::atan(1.0f / proj11) * (180.0 / 3.14159265358979323846));
	camera_matrix_postprocess_rotate(rcam);
	
	// read far plane
	nbytesread = 0;
	const uint64_t far_plane_offset = 0x23FB310ull;
	float far_plane_distance = g_far_plane_distance;
	if (tryreadmemory(gamename_verbose() + std::string("_far_plane"), errstr, mygame_handle_exe,
		(LPCVOID)(dll_base + far_plane_offset), reinterpret_cast<LPVOID>(&far_plane_distance),
		sizeof(far_plane_distance), &nbytesread)) {
		g_far_plane_distance = far_plane_distance;
	}

	// //log far plane distance
	// char logbuf[96];
	// std::snprintf(logbuf, sizeof(logbuf), "[Crysis] far plane distance: %.6f", static_cast<double>(far_plane_distance));
	// reshade::log_message(reshade::log_level::info, logbuf);


	// char linebuf[160];
	// for (int row = 0; row < 3; ++row) {
	// 	std::snprintf(linebuf, sizeof(linebuf), "[Crysis] row %d: %.6f %.6f %.6f %.6f", row,
	// 		static_cast<double>(cambuf[row * 4 + 0]), static_cast<double>(cambuf[row * 4 + 1]),
	// 		static_cast<double>(cambuf[row * 4 + 2]), static_cast<double>(cambuf[row * 4 + 3]));
	// 	reshade::log_message(reshade::log_level::info, linebuf);
	// }

	++g_crysis_translation_log_counter;
	if (g_crysis_translation_log_interval_frames > 0 &&
		(g_crysis_translation_log_counter % static_cast<uint64_t>(g_crysis_translation_log_interval_frames) == 0)) {
		const CamMatrix& M = rcam.extrinsic_cam2world;
		char translation_log[160];
		std::snprintf(translation_log, sizeof(translation_log),
			"[Crysis] translation (frame %llu): %.6f %.6f %.6f",
			static_cast<unsigned long long>(g_crysis_translation_log_counter),
			static_cast<double>(M(0, cam_matrix_position_column)),
			static_cast<double>(M(1, cam_matrix_position_column)),
			static_cast<double>(M(2, cam_matrix_position_column)));
		reshade::log_message(reshade::log_level::info, translation_log);
	}

	return true;
}
