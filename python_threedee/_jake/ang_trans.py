import numpy as np

def euler_yaw_pitch_roll_to_matrix(yaw, pitch, roll):
    """
    Convert yaw, pitch, roll (in radians) to a 3x3 rotation matrix.
    Coordinate system assumption:
        World: X right, Y forward, Z up (CryEngine-style).
    Rotation order:
        1) yaw   around +Z (world up)
        2) pitch around +X (right)
        3) roll  around +Y (forward)
    Returns:
        R_c2w: 3x3 rotation matrix from camera coordinates to world coordinates.
    """
    cy, sy = np.cos(yaw), np.sin(yaw)
    cp, sp = np.cos(pitch), np.sin(pitch)
    cr, sr = np.cos(roll), np.sin(roll)

    # Combined rotation matrix R = R_yaw * R_pitch * R_roll
    r00 = cy * cr - sy * sp * sr
    r01 = -sy * cp
    r02 = cy * sr + sy * sp * cr
    r10 = sy * cr + cy * sp * sr
    r11 = cy * cp
    r12 = sy * sr - cy * sp * cr
    r20 = -cp * sr
    r21 = sp
    r22 = cp * cr

    R_c2w = np.array([
        [r00, r01, r02],
        [r10, r11, r12],
        [r20, r21, r22],
    ])

    # # Alternative construction using individual rotation matrices:
    # # Yaw: rotate around world Z axis
    # R_yaw = np.array([
    #     [cy, -sy, 0.0],
    #     [sy,  cy, 0.0],
    #     [0.0, 0.0, 1.0],
    # ])

    # # Pitch: rotate around world X axis
    # R_pitch = np.array([
    #     [1.0, 0.0, 0.0],
    #     [0.0,  cp, -sp],
    #     [0.0,  sp,  cp],
    # ])

    # # Roll: rotate around world Y axis
    # R_roll = np.array([
    #     [ cr, 0.0, sr],
    #     [0.0, 1.0, 0.0],
    #     [-sr, 0.0, cr],
    # ])

    # # Apply yaw -> pitch -> roll (extrinsic rotations around world axes)
    # R_c2w = R_yaw @ R_pitch @ R_roll
    return R_c2w


def ang_to_R_cam_to_world(ang):
    """
    ang: (yaw, pitch, roll) in radians, from game ANG.
    Returns:
        3x3 rotation matrix R_c2w: camera -> world.
    """
    yaw, pitch, roll = ang
    return euler_yaw_pitch_roll_to_matrix(yaw, pitch, roll)


if __name__ == "__main__":
    # Example ANG from your observation
    ang = (0.09367356449365616, -0.40014442801475525, -0.0)

    R_c2w = ang_to_R_cam_to_world(ang)

    np.set_printoptions(precision=6, suppress=True)
    print("R (camera -> world):")
    print(R_c2w)
