// Copyright (C) 2022 Jason Bunk
#include "Crysis.h"
#include "gcv_utils/memread.h"
#include <cstdint>
#include <cmath>
#include <cstring>
#include <reshade.hpp>
#include <cstdio>

std::string GameCrysis::gamename_verbose() const { return "Crysis2008_GOG_DX10_x64"; } // tested for this build

std::string GameCrysis::camera_dll_name() const { return "Cry3DEngine.dll"; }
uint64_t GameCrysis::camera_dll_mem_start() const { return 0x2008F0ull; }
GameCamDLLMatrixType GameCrysis::camera_dll_matrix_format() const { return GameCamDLLMatrix_3x4; }

bool GameCrysis::can_interpret_depth_buffer() const {
	return true;
}

#define NEAR_PLANE_DISTANCE 0.25

// need to scan far plane in memory because it seems to change per level?
#define FAR_PLANE_DISTANCE 5000.0

static float g_far_plane_distance = FAR_PLANE_DISTANCE;

float GameCrysis::convert_to_physical_distance_depth_u64(uint64_t depthval) const {
	const float far_plane_distance = g_far_plane_distance;
	const double znorm = static_cast<double>(depthval) / 16777215.0;
	return static_cast<float>(NEAR_PLANE_DISTANCE / std::max(0.0000001, 1.0 - znorm * (1.0 - NEAR_PLANE_DISTANCE / far_plane_distance)));
}

bool GameCrysis::get_camera_matrix(CamMatrixData& rcam, std::string& errstr) {
	if (!GameWithCameraDataInOneDLL::get_camera_matrix(rcam, errstr)) {
		return false;
	}
	const Eigen::Matrix<ftype, 3, 1> c2w_col1 = rcam.extrinsic_cam2world.col(1);
	rcam.extrinsic_cam2world.col(1) = rcam.extrinsic_cam2world.col(2);
	rcam.extrinsic_cam2world.col(2) = -c2w_col1;

	HMODULE render_module = GetModuleHandleW(L"CryRenderD3D10.dll");
	if (render_module == nullptr) {
		errstr += "[Crysis] failed to get CryRenderD3D10.dll module handle for proj11";
		return false;
	}

	HMODULE engine_module = camera_dll != 0 ? camera_dll : GetModuleHandleW(L"Cry3DEngine.dll");
	if (engine_module == nullptr) {
		errstr += "[Crysis] failed to get Cry3DEngine.dll module handle for far plane";
		return false;
	}

	SIZE_T nbytesread = 0;

	const UINT_PTR render_base = reinterpret_cast<UINT_PTR>(render_module);
	const uint64_t proj11_offset = 0x65A854ull;
	float proj11 = 0.0f;
	if (!tryreadmemory(gamename_verbose() + std::string("_proj11"), errstr, mygame_handle_exe,
		(LPCVOID)(render_base + proj11_offset), reinterpret_cast<LPVOID>(&proj11),
		sizeof(proj11), &nbytesread)) {
		return false;
	}
	rcam.fov_v_degrees = static_cast<float>(2.0 * std::atan(1.0f / proj11) * (180.0 / 3.14159265358979323846));

	nbytesread = 0;
	float far_plane_distance = g_far_plane_distance;
	const UINT_PTR engine_base = reinterpret_cast<UINT_PTR>(engine_module);
	const uint64_t far_plane_offset = 0x200950ull;
	if (tryreadmemory(gamename_verbose() + std::string("_far_plane"), errstr, mygame_handle_exe,
		(LPCVOID)(engine_base + far_plane_offset), reinterpret_cast<LPVOID>(&far_plane_distance),
		sizeof(far_plane_distance), &nbytesread)) {
		g_far_plane_distance = far_plane_distance;
	}

	return true;
}
