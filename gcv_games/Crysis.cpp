// Copyright (C) 2022 Jason Bunk
#include "Crysis.h"
#include "gcv_utils/memread.h"
#include <cstdint>
#include <cmath>
#include <reshade.hpp>
#include <cstdio>

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
	// static float far_plane_distance = FAR_PLANE_DISTANCE;
	// if (!init_in_game()) return false;

	// // read far plane
	// const UINT_PTR dll_base = static_cast<UINT_PTR>(reinterpret_cast<uintptr_t>(camera_dll));
	// float far_plane_read = FAR_PLANE_DISTANCE;
	// SIZE_T nbytesread = 0;
	// const uint64_t far_plane_offset = 0x23FB4E0ull;
	// std::string err;
	// if (tryreadmemory(gamename_verbose() + std::string("_far_plane"), err, mygame_handle_exe,
	// 	(LPCVOID)(dll_base + far_plane_offset), reinterpret_cast<LPVOID>(&far_plane_read), sizeof(far_plane_read), &nbytesread)) {
	// 	far_plane_distance = far_plane_read;
	// } else if (!err.empty()) {
	// 	reshade::log_message(reshade::log_level::warning, err.c_str());
	// }
	const float far_plane_distance = g_far_plane_distance;
	// static bool far_plane_initialized = false;
	// if (!far_plane_initialized) {
	// 	far_plane_initialized = true;
	// 	if (mygame_handle_exe == 0) {
	// 		const_cast<GameCrysis*>(this)->init_get_game_exe();
	// 	}
	// 	HMODULE exe_module = (camera_dll != 0) ? camera_dll : GetModuleHandle(nullptr);
	// 	if (exe_module != nullptr) {
	// 		const void* far_plane_addr = reinterpret_cast<const void*>(reinterpret_cast<uintptr_t>(exe_module) + 0x23FB310ull);
	// 		SIZE_T bytes_read = 0;
	// 		float far_plane_read = FAR_PLANE_DISTANCE;
	// 		std::string err;
	// 		if (tryreadmemory(gamename_verbose() + std::string("_far_plane"), err, mygame_handle_exe,
	// 			far_plane_addr, reinterpret_cast<LPVOID>(&far_plane_read), sizeof(far_plane_read), &bytes_read)) {
	// 			far_plane_distance = far_plane_read;
	// 			char logbuf[96];
	// 			std::snprintf(logbuf, sizeof(logbuf), "[Crysis] far plane distance: %.6f", static_cast<double>(far_plane_distance));
	// 			reshade::log_message(reshade::log_level::info, logbuf);
	// 		} else if (!err.empty()) {
	// 			reshade::log_message(reshade::log_level::warning, err.c_str());
	// 		}
	// 	}
	// }
	
	// convert to physical distance
	const double znorm = static_cast<double>(depthval) / 16777215.0;
	return static_cast<float>(NEAR_PLANE_DISTANCE / std::max(0.0000001, 1.0 - znorm * (1.0 - NEAR_PLANE_DISTANCE / far_plane_distance)));
}

bool GameCrysis::get_camera_matrix(CamMatrixData& rcam, std::string& errstr) {
	rcam.extrinsic_status = CamMatrix_Uninitialized;
	if (!init_in_game()) return false;

	// read pos
	const UINT_PTR dll_base = static_cast<UINT_PTR>(reinterpret_cast<uintptr_t>(camera_dll));
	float cambuf[12] = {};
	SIZE_T nbytesread = 0;
	const uint64_t cam_translation_offset = 0x23FB4E0ull;
	float cam_translation[3];
	if (!tryreadmemory(gamename_verbose() + std::string("_cam_translation"), errstr, mygame_handle_exe,
		(LPCVOID)(dll_base + cam_translation_offset), reinterpret_cast<LPVOID>(cam_translation),
		sizeof(cam_translation), &nbytesread)) {
		return false;
	}
	for (int row = 0; row < 3; ++row) {
		cambuf[row * 4 + 3] = cam_translation[row];
	}
	
	// read angles
	float angbuf[3];
	const uint64_t ang_offset = 0x7EEA9C8ull;
	if (!tryreadmemory(gamename_verbose() + std::string("_angles"), errstr, mygame_handle_exe,
		(LPCVOID)(dll_base + ang_offset), reinterpret_cast<LPVOID>(angbuf),
		sizeof(angbuf), &nbytesread)) {
		return false;
	}
	const float yaw = angbuf[0];
	const float pitch = angbuf[1];
	const float roll = angbuf[2];
	const float cy = std::cos(yaw), sy = std::sin(yaw);
	const float cp = std::cos(pitch), sp = std::sin(pitch);
	const float cr = std::cos(roll), sr = std::sin(roll);

	const float r00 = cy * cr - sy * sp * sr;
	const float r01 = -sy * cp;
	const float r02 = cy * sr + sy * sp * cr;
	const float r10 = sy * cr + cy * sp * sr;
	const float r11 = cy * cp;
	const float r12 = sy * sr - cy * sp * cr;
	const float r20 = -cp * sr;
	const float r21 = sp;
	const float r22 = cp * cr;

	// convert to opengl style (right-handed)
	cambuf[1] = r02; cambuf[2] = -r01;
	cambuf[5] = r12; cambuf[6] = -r11;
	cambuf[9] = r22; cambuf[10] = -r21;

	// read fov
	const uint64_t proj00_offset = 0x7D68FF4ull;
	float proj00 = 0.0f;
	if (!tryreadmemory(gamename_verbose() + std::string("_proj00"), errstr, mygame_handle_exe,
		(LPCVOID)(dll_base + proj00_offset), reinterpret_cast<LPVOID>(&proj00),
		sizeof(proj00), &nbytesread)) {
		return false;
	}
	rcam.fov_h_degrees = static_cast<float>(2.0 * std::atan(1.0f / proj00) * (180.0 / 3.14159265358979323846));
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
	
	// log cam matrix
	char header[128];
	std::snprintf(header, sizeof(header), "[Crysis] cam matrix @ +0x%llX", static_cast<unsigned long long>(cam_translation_offset));
	reshade::log_message(reshade::log_level::info, header);
	char linebuf[160];
	for (int row = 0; row < 3; ++row) {
		std::snprintf(linebuf, sizeof(linebuf), "[Crysis] row %d: %.6f %.6f %.6f %.6f", row,
			static_cast<double>(cambuf[row * 4 + 0]), static_cast<double>(cambuf[row * 4 + 1]),
			static_cast<double>(cambuf[row * 4 + 2]), static_cast<double>(cambuf[row * 4 + 3]));
		reshade::log_message(reshade::log_level::info, linebuf);
	}

	return true;
}
