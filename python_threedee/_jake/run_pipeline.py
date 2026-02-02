import os
import subprocess
import sys

# ====== User configuration ======
SCRIPT_DIR = r"C:\Users\user\Desktop\project\gamehack\reshade_cv_version2.0\python_threedee"
DATA_DIR = r"D:\SteamLibrary\steamapps\common\Horizon Forbidden West Complete Edition\cv_saved\f11-mode"

# If you want to force a specific Python from a conda env:
# PYTHON_EXE = r"C:\Users\user\miniconda3\envs\yourenv\python.exe"
# Otherwise use the current interpreter:
PYTHON_EXE = sys.executable
# ================================


def run(cmd, cwd=None):
    print(">>>", " ".join(cmd))
    subprocess.run(cmd, check=True, cwd=cwd)


def main():
    # Step 1: unpack h5 and video into frames
    cmd1 = [
        PYTHON_EXE,
        os.path.join(SCRIPT_DIR, "unpack_h5_and_video.py"),
        DATA_DIR,
    ]
    # run(cmd1)

    # Step 2: build point cloud using load_point_cloud_SUFFIX.py
    depth_pattern = os.path.join(DATA_DIR, "frame_*.npy")
    output_path = os.path.join(DATA_DIR, "output.ply")

    cmd2 = [
        PYTHON_EXE,
        os.path.join(SCRIPT_DIR, "load_point_cloud_ue.py"),  # load_point_cloud.py  load_point_cloud_re2.py
        depth_pattern,
        "-max", "50.0",
        "-ss", "5",
        "-o", output_path,
    ]
    run(cmd2, cwd=DATA_DIR)

    print("All done.")


if __name__ == "__main__":
    main()
