import re
from pathlib import Path

# ====== User configuration ======
DATA_DIR = r"C:\_Relax\Steam\steamapps\common\Crysis Remastered\Bin64\cv_saved\f11_mode"
# ================================

STANDARD_PATTERN = re.compile(r"^frame_(\d{6})_(depth|RGB|meta|camera)\.(npy|png|json)$")


def rename_files(data_dir: Path) -> None:
    files = sorted([p for p in data_dir.iterdir() if p.is_file()])

    for path in files:
        match = STANDARD_PATTERN.match(path.name)
        if not match:
            continue

        old_index = int(match.group(1))
        new_index = old_index // 3

        if new_index == old_index:
            continue

        stem = match.group(2)
        new_name = f"frame_{new_index:06d}_{stem}{path.suffix}"
        target_path = data_dir / new_name

        if target_path.exists():
            raise FileExistsError(f"Target already exists: {target_path}")

        print(f"Renaming {path.name} -> {new_name}")
        path.rename(target_path)


def main():
    data_dir = Path(DATA_DIR)
    if not data_dir.exists():
        raise FileNotFoundError(f"DATA_DIR does not exist: {data_dir}")

    rename_files(data_dir)


if __name__ == "__main__":
    main()
