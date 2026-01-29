# check_npy_minmax.py
from pathlib import Path
import numpy as np

# ====== “宏定义”区域：只改这里 ======
DATA_DIR = r"D:\SteamLibrary\steamapps\common\Resident Evil Village BIOHAZARD VILLAGE\cv_saved\ResidentEvil8_2026-01-29_69640404_depth.npy"
# =====================================


def main():
    npy_path = Path(DATA_DIR)
    if not npy_path.exists():
        raise FileNotFoundError(f"文件不存在：{npy_path}")

    # mmap_mode="r"：不把整个数组一次性全塞进内存（对大文件更友好）
    arr = np.load(npy_path, mmap_mode="r", allow_pickle=False)

    print(f"Path : {npy_path}")
    print(f"Shape: {arr.shape}")
    print(f"DType: {arr.dtype}")

    # 如果是浮点/复数，可能出现 NaN；用 nanmin/nanmax 更稳
    if np.issubdtype(arr.dtype, np.floating) or np.issubdtype(arr.dtype, np.complexfloating):
        vmin = np.nanmin(arr)
        vmax = np.nanmax(arr)
        print("Min  : (nan-ignored)", vmin)
        print("Max  : (nan-ignored)", vmax)
    else:
        print("Min  :", arr.min())
        print("Max  :", arr.max())


if __name__ == "__main__":
    main()