import json
from pathlib import Path
import math
import sys
import numpy as np

DATA_DIR = Path(r"D:\SteamLibrary\steamapps\common\God of War Ragnarok\cv_saved\actions_2026-01-30_56871928")
TARGET_FOV = 60

_CAM_ANGLES = (
    (-0.559816, 0.058274, -0.000000),
    (-0.559816, 0.058274, -0.000000),
    (-0.559816, 0.058362, -0.000000),
    (-0.559816, 0.058375, -0.000000),
    (-0.559816, 0.058362, 0.000000),
    (-0.559816, 0.058334, -0.000000),
    (-0.559816, 0.058311, -0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
    (-0.559816, 0.058298, 0.000000),
)


def _rotation_matrix_from_euler_angles_ue_to_opengl(
    yaw: float, pitch: float, roll: float
) -> tuple[float, float, float, float, float, float, float, float, float]:
    cos = math.cos
    sin = math.sin
    cy = cos(yaw)
    sy = sin(yaw)
    cp = cos(pitch)
    sp = sin(pitch)
    cr = cos(roll)
    sr = sin(roll)

    r00 = cy * cr - sy * sp * sr
    r01 = -sy * cp
    r02 = cy * sr + sy * sp * cr
    r10 = sy * cr + cy * sp * sr
    r11 = cy * cp
    r12 = sy * sr - cy * sp * cr
    r20 = -cp * sr
    r21 = sp
    r22 = cp * cr

    return (r00, r02, -r01, r10, r12, -r11, r20, r22, -r21)


_CAM_ROTATIONS_UE_TO_OPENGL = tuple(
    _rotation_matrix_from_euler_angles_ue_to_opengl(*ang) for ang in _CAM_ANGLES
)


def edit_value(path: Path) -> None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return

    if not isinstance(data, dict):
        return

    if data.get("fov_h_degrees") == TARGET_FOV:
        return

    data["fov_h_degrees"] = TARGET_FOV
    # data["fov_h_degrees"] /= 1.25
    path.write_text(json.dumps(data, ensure_ascii=True), encoding="utf-8")


def print_value(path: Path, key: str) -> None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return

    if isinstance(data, dict) and key in data:
        print(f"{path}: {data[key]}")


def edit_key(path: Path) -> None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return

    if not isinstance(data, dict):
        return

    # if "fov_v_degrees" in data or "fov_h_degrees" not in data:
    #     return

    data["fov_v_degrees"] = data.pop("fov_h_degrees")
    path.write_text(json.dumps(data, ensure_ascii=True), encoding="utf-8")


def edit_cam2world(path: Path, key: str = "extrinsic_cam2world") -> None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return

    if not isinstance(data, dict):
        return

    cam2world = np.array(data['extrinsic_cam2world'], dtype=np.float64).reshape(3, 4)
    try:
        # Treat as 3x4 row-major:   1,2,3,4,11,12,13,14,21,22,23,24
        # R_cv = cam2world[:, :3]  # 3x3旋转矩阵（UE系）
        # R_cv_new = R_cv.copy()
        # R_cv_new[:, 1] *= -1.0
        # R_cv_new[2, :] *= -1.0
        # cam2world[:, :3] = R_cv_new


        # t_cv = cam2world[:, 3]   # 3x1平移向量（UE系，未缩放）
        # t_cv_new = t_cv.copy()
        # t_cv_new[0] = t_cv[2]
        # t_cv_new[1] = t_cv[0]
        # t_cv_new[2] = t_cv[1]
        # t_cv_new[2] *= -1.0
        # cam2world[:, 3] = t_cv_new

        data['extrinsic_cam2world'] = cam2world.reshape(-1).tolist()
        print("finished edit_cam2world")
    except Exception:
        return

    path.write_text(json.dumps(data, ensure_ascii=True, separators=(",", ":")), encoding="utf-8")

def calc_rotation_matrix_from_euler_angles(path: Path) -> None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return

    if not isinstance(data, dict):
        return

    try:
        frame_index = int(data["frame_idx"])
        r00, r01, r02, r10, r11, r12, r20, r21, r22 = _CAM_ROTATIONS_UE_TO_OPENGL[
            frame_index
        ]
        print(f"calc frame_index: {frame_index}")
    except Exception:
        return

    extrinsic = data.get("extrinsic_cam2world")
    if not isinstance(extrinsic, list) or len(extrinsic) != 12:
        extrinsic = [0.0] * 12

    extrinsic[0] = r00
    extrinsic[1] = r01
    extrinsic[2] = r02
    extrinsic[4] = r10
    extrinsic[5] = r11
    extrinsic[6] = r12
    extrinsic[8] = r20
    extrinsic[9] = r21
    extrinsic[10] = r22
    data["extrinsic_cam2world"] = extrinsic

    path.write_text(json.dumps(data, ensure_ascii=True, separators=(",", ":")), encoding="utf-8")

# def main() -> None:
#     yaw, pitch, roll = -2.867747, 0.556976, 0.0

#     m00, m01, m02, m10, m11, m12, m20, m21, m22 = _rotation_matrix_from_euler_angles_ue_to_opengl(
#         yaw, pitch, roll
#     )
#     sys.stdout.write(
#         f"{m00} {m01} {m02}\n{m10} {m11} {m12}\n{m20} {m21} {m22}\n"
#     )

# def main() -> None:
#     root = DATA_DIR
#     if not root.exists():
#         raise SystemExit(f"DATA_DIR does not exist: {root}")
    
#     for json_file in root.rglob("*.json"):
#         calc_rotation_matrix_from_euler_angles(json_file)

def main() -> None:
    root = DATA_DIR
    if not root.exists():
        raise SystemExit(f"DATA_DIR does not exist: {root}")

    for json_file in root.rglob("*.json"):
        # edit_value(json_file)
        # edit_key(json_file)
        edit_cam2world(json_file)
        # print_value(json_file, "fov_h_degrees")

if __name__ == "__main__":
    main()
