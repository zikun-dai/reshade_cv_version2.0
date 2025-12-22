#!/usr/bin/env python3
import os
import json
import argparse
import numpy as np


def load_cam_json(path):
    with open(path, "r", encoding="utf-8") as f:
        j = json.load(f)
    assert "extrinsic_cam2world" in j, f"no extrinsic_cam2world in {path}"
    arr = np.asarray(j["extrinsic_cam2world"], dtype=np.float64).reshape(3, 4)
    R = arr[:, :3]
    t = arr[:, 3]
    return R, t, j


def cam_center_cam2world(R, t):
    # 约定 [R | t] 把相机坐标变到世界坐标，则相机中心 = t
    return t


def cam_center_world2cam(R, t):
    # 约定 [R | t] 把世界坐标变到相机坐标，则相机中心 = -R^T t
    return -R.T @ t


def main():
    ap = argparse.ArgumentParser(
        description="Check RE2 extrinsic_cam2world for consistency."
    )
    ap.add_argument("data_dir", help="e.g. python_threedee/actions_2025-11-19_757459012")
    ap.add_argument(
        "--frames",
        type=str,
        default="5,10,15,20",
        help="comma-separated frame indices, e.g. '0,10,20'",
    )
    args = ap.parse_args()

    frame_indices = [int(x) for x in args.frames.split(",") if x.strip() != ""]

    print(f"Checking frames: {frame_indices}")
    cam2_centers = []
    world2_centers = []

    for idx in frame_indices:
        cam_path = os.path.join(args.data_dir, f"frame_{idx:06d}_camera.json")
        if not os.path.isfile(cam_path):
            print(f"[WARN] missing {cam_path}")
            continue

        R, t, meta = load_cam_json(cam_path)
        c_cam2 = cam_center_cam2world(R, t)
        c_world2 = cam_center_world2cam(R, t)
        cam2_centers.append(c_cam2)
        world2_centers.append(c_world2)

        print(f"\nFrame {idx}:")
        print("  extrinsic_cam2world (3x4):")
        print(R, t.reshape(3, 1), sep="\n")
        print("  center_if_cam2world:", c_cam2)
        print("  center_if_world2cam:", c_world2)
        if "fov_h_degrees" in meta:
            print("  fov_h_degrees:", meta["fov_h_degrees"])
        if "fov_v_degrees" in meta:
            print("  fov_v_degrees:", meta["fov_v_degrees"])

    if len(cam2_centers) >= 2:
        cam2_centers = np.vstack(cam2_centers)
        world2_centers = np.vstack(world2_centers)
        print("\n=== Summary ===")
        print("cam2world centers (first 3):")
        print(cam2_centers[:3])
        print("world2cam centers (first 3):")
        print(world2_centers[:3])
        print("cam2world center bbox:", cam2_centers.min(axis=0), "->", cam2_centers.max(axis=0))
        print("world2cam center bbox:", world2_centers.min(axis=0), "->", world2_centers.max(axis=0))


if __name__ == "__main__":
    main()
