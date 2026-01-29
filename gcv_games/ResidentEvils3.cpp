// Copyright (C) 2022 Jason Bunk
#include "ResidentEvils3.h"
#include "gcv_utils/depth_utils.h"
#include "gcv_utils/scripted_cam_buf_templates.h"


std::string GameResidentEvils3::gamename_verbose() const { return "GameResidentEvils3"; } // hopefully continues to work with future patches via the mod lua

std::string GameResidentEvils3::camera_dll_name() const { return ""; } // no dll name, it's available in the exe memory space
uint64_t GameResidentEvils3::camera_dll_mem_start() const { return 0; }
GameCamDLLMatrixType GameResidentEvils3::camera_dll_matrix_format() const { return GameCamDLLMatrix_allmemscanrequiredtofindscriptedcambuf; }

scriptedcam_checkbuf_funptr GameResidentEvils3::get_scriptedcambuf_checkfun() const {
	return template_check_scriptedcambuf_hash<double, 13, 1>;
}
uint64_t GameResidentEvils3::get_scriptedcambuf_sizebytes() const {
	return template_scriptedcambuf_sizebytes<double, 13, 1>();
}
bool GameResidentEvils3::copy_scriptedcambuf_to_matrix(uint8_t* buf, uint64_t buflen, CamMatrixData& rcam, std::string& errstr) const {
	return template_copy_scriptedcambuf_extrinsic_cam2world_and_fov<double, 13, 1>(buf, buflen, rcam, false, errstr);
}

bool GameResidentEvils3::can_interpret_depth_buffer() const {
	return true;
}
float GameResidentEvils3::convert_to_physical_distance_depth_u64(uint64_t depthval) const {
	const double normalizeddepth = static_cast<double>(depthval) / 4294967295.0;
	// This game has a logarithmic depth buffer with unknown constant(s).
	// These numbers were found by a curve fit, so are approximate.
	return 1.28 / (0.0004253421645545 + exp_fast_approx(354.8489261773826 * normalizeddepth - 83.12790960252826));
}

uint64_t GameResidentEvils3::get_scriptedcambuf_triggerbytes() const
{
    // 将 double 类型的注入专用魔数转换为 8 字节的整数
    const double magic_double = 1.20040525131452021e-12;
    uint64_t magic_int;
    static_assert(sizeof(magic_double) == sizeof(magic_int));
    memcpy(&magic_int, &magic_double, sizeof(magic_int));
    return magic_int;
}

void GameResidentEvils3::process_camera_buffer_from_igcs(
    double* camera_data_buffer,
    const float* camera_ue_pos, // 对应 Python 中的 location {x, y, z}
    float roll, float pitch, float yaw, // 弧度（对应 rotation['roll'], ['pitch'], ['yaw']）
    float fov)
{
    // --- 严格对齐 Python 脚本逻辑 ---

    // 步骤 1: 计算 UE 坐标系下的旋转矩阵 R_ue (C2W)
    // Python: R_ue = ue_rotator_to_R_world(rotation['roll'], -rotation['pitch'], -rotation['yaw'])
    const float rx = roll;          // 对应 rotation['roll']（无符号变化）
    const float ry = -pitch;        // 对应 -rotation['pitch']（pitch 取负）
    const float rz = -yaw;          // 对应 -rotation['yaw']（yaw 取负）

    // 计算旋转矩阵的三角函数值（匹配 Python 的 rot_x_lh/rot_y_lh/rot_z_lh）
    const float cr = cos(rx), sr = sin(rx); // Rx: 绕 X 轴旋转（roll）
    const float cy = cos(ry), sy = sin(ry); // Ry: 绕 Y 轴旋转（-pitch）
    const float cz = cos(rz), sz = sin(rz); // Rz: 绕 Z 轴旋转（-yaw）

    // 定义旋转矩阵（与 Python 矩阵结构完全一致）
    // R_x(roll) - rot_x_lh
    const float Rx[3][3] = {
        { 1,   0,    0   },
        { 0,  cr,   sr   },
        { 0, -sr,   cr   }
    };
    // R_y(-pitch) - rot_y_lh
    const float Ry[3][3] = {
        { cy,   0,  -sy  },
        {  0,   1,    0   },
        { sy,   0,   cy  }
    };
    // R_z(-yaw) - rot_z_lh
    const float Rz[3][3] = {
        { cz,  sz,    0   },
        { -sz, cz,    0   },
        {  0,   0,    1   }
    };

    // 计算 R_ue = Rz @ Ry @ Rx（Python 乘法顺序：Z→Y→X  extrinsic 旋转）
    float R_ue_temp[3][3] = {0}; // 临时存储 Rz @ Ry
    float R_ue[3][3] = {0};      // 最终 R_ue = (Rz @ Ry) @ Rx

    // 第一步：计算 Rz @ Ry
    for (int i = 0; i < 3; ++i) {
        for (int j = 0; j < 3; ++j) {
            R_ue_temp[i][j] = 0.0f;
            for (int k = 0; k < 3; ++k) {
                R_ue_temp[i][j] += Rz[i][k] * Ry[k][j];
            }
        }
    }

    // 第二步：计算 (Rz @ Ry) @ Rx
    for (int i = 0; i < 3; ++i) {
        for (int j = 0; j < 3; ++j) {
            R_ue[i][j] = 0.0f;
            for (int k = 0; k < 3; ++k) {
                R_ue[i][j] += R_ue_temp[i][k] * Rx[k][j];
            }
        }
    }

    // 步骤 2: 转换到 OpenCV 坐标系（R_cv = M_UE_to_CV @ R_ue @ M_UE_to_CV.T）
    const float M_UE_to_CV[3][3] = {
        { 0, 1,  0 },
        { 0, 0, -1 },
        { 1, 0,  0 }
    };
    // M_UE_to_CV 的转置矩阵（提前计算，与 Python 中的 .T 操作一致）
    const float M_UE_to_CV_T[3][3] = {
        { 0,  0, 1 },
        { 1,  0, 0 },
        { 0, -1, 0 }
    };

    float R_cv_temp[3][3] = {0}; // 临时存储 R_ue @ M_UE_to_CV.T
    float R_cv[3][3] = {0};      // 最终 R_cv = M_UE_to_CV @ (R_ue @ M_UE_to_CV.T)

    // 第一步：计算 R_ue @ M_UE_to_CV.T
    for (int i = 0; i < 3; ++i) {
        for (int j = 0; j < 3; ++j) {
            R_cv_temp[i][j] = 0.0f;
            for (int k = 0; k < 3; ++k) {
                R_cv_temp[i][j] += R_ue[i][k] * M_UE_to_CV_T[k][j];
            }
        }
    }

    // 第二步：计算 M_UE_to_CV @ R_cv_temp
    for (int i = 0; i < 3; ++i) {
        for (int j = 0; j < 3; ++j) {
            R_cv[i][j] = 0.0f;
            for (int k = 0; k < 3; ++k) {
                R_cv[i][j] += M_UE_to_CV[i][k] * R_cv_temp[k][j];
            }
        }
    }

    // 步骤 3: 计算平移向量 t_cv（匹配 Python 逻辑）
    // Python: t_cv = [location['x'], -location['z'], location['y']] * pose_scale(0.5)
    // camera_ue_pos[0] = x, [1] = y, [2] = z
    const float pose_scale = 0.2f; // 脚本中 pose_scale = 0.5
    const float t_cv[3] = {
        camera_ue_pos[0] * pose_scale,  // t_cv[0] = location['x'] * 0.5
        -camera_ue_pos[1] * pose_scale, // t_cv[1] = -location['z'] * 0.5
        -camera_ue_pos[2] * pose_scale   // t_cv[2] = location['y'] * 0.5
    };

    // 步骤 4: 填充 c2w 矩阵到缓冲区（4x4 矩阵的旋转和平移部分）
    // 第一行: [R_cv[0][0], R_cv[0][1], R_cv[0][2], t_cv[0]]
    camera_data_buffer[2] = R_cv[0][0];
    camera_data_buffer[3] = -R_cv[0][1];
    camera_data_buffer[4] = -R_cv[0][2];
    camera_data_buffer[5] = t_cv[0];

    // 第二行: [R_cv[1][0], R_cv[1][1], R_cv[1][2], t_cv[1]]
    camera_data_buffer[6] = R_cv[1][0];
    camera_data_buffer[7] = -R_cv[1][1];
    camera_data_buffer[8] = -R_cv[1][2];
    camera_data_buffer[9] = t_cv[1];

    // 第三行: [R_cv[2][0], R_cv[2][1], R_cv[2][2], t_cv[2]]
    camera_data_buffer[10] = R_cv[2][0];
    camera_data_buffer[11] = -R_cv[2][1];
    camera_data_buffer[12] = -R_cv[2][2];
    camera_data_buffer[13] = t_cv[2];

    // FOV（与 Python 一致，使用 fovx_deg）
    camera_data_buffer[14] = fov;
}