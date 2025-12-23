import re
from pathlib import Path

# ====== User configuration ======
DATA_DIR = r"C:\\_Relax\\Steam\\steamapps\\common\\Crysis Remastered\\Bin64\\cv_saved\\f11_mode"
# ================================

ALLOWED_SUFFIXES = ["_depth.npy", "_RGB.png", "_meta.json", "_camera.json"]
STANDARD_PATTERN = re.compile(r"^frame_(\d{6})_(depth|RGB|meta|camera)\.(npy|png|json)$")


def cleanup_directory(data_dir: Path) -> None:
    """Remove files that do not match the allowed suffixes."""
    for path in data_dir.iterdir():
        if path.is_file() and not any(path.name.endswith(suffix) for suffix in ALLOWED_SUFFIXES):
            print(f"Removing {path.name}")
            path.unlink()


def parse_existing_indices(files):
    indices = set()
    for path in files:
        match = STANDARD_PATTERN.match(path.name)
        if match:
            indices.add(int(match.group(1)))
    return indices


def next_available_index(indices, start: int) -> int:
    idx = start
    while idx in indices:
        idx += 1
    return idx


def rename_files(data_dir: Path) -> None:
    files = sorted([p for p in data_dir.iterdir() if p.is_file()])

    existing_indices = parse_existing_indices(files)
    max_existing = max(existing_indices) if existing_indices else -1
    next_idx = max_existing + 1

    grouped_paths = {}
    group_order = []

    for path in files:
        # Skip files already in the desired format
        if STANDARD_PATTERN.match(path.name):
            continue

        suffix_match = next((suffix for suffix in ALLOWED_SUFFIXES if path.name.endswith(suffix)), None)
        if not suffix_match:
            continue

        prefix = path.name[: -len(suffix_match)]
        if prefix not in grouped_paths:
            grouped_paths[prefix] = []
            group_order.append(prefix)
        grouped_paths[prefix].append(path)

    for prefix in group_order:
        target_index = next_available_index(existing_indices, next_idx)
        next_idx = target_index + 1

        for path in sorted(grouped_paths[prefix], key=lambda p: p.name):
            suffix_match = next((suffix for suffix in ALLOWED_SUFFIXES if path.name.endswith(suffix)), None)
            if not suffix_match:
                continue

            stem = suffix_match.split(".")[0].lstrip("_")
            new_name = f"frame_{target_index:06d}_{stem}{path.suffix}"
            target_path = data_dir / new_name

            print(f"Renaming {path.name} -> {new_name}")
            path.rename(target_path)

        existing_indices.add(target_index)


def main():
    data_dir = Path(DATA_DIR)
    if not data_dir.exists():
        raise FileNotFoundError(f"DATA_DIR does not exist: {data_dir}")

    cleanup_directory(data_dir)
    rename_files(data_dir)


if __name__ == "__main__":
    main()
