import argparse
import re
from pathlib import Path
from typing import Iterable, List, Sequence, Tuple

DEFAULT_LOG_PATH = r"C:\_Relax\Steam\steamapps\common\Crysis Remastered\Bin64\ReShade.log"
TRANSLATION_PATTERN = re.compile(
    r"translation(?:\s*\(frame\s*(\d+)\))?\s*:\s*([-+eE0-9\.]+)\s+([-+eE0-9\.]+)\s+([-+eE0-9\.]+)",
    re.IGNORECASE,
)


def parse_translations(lines: Iterable[str]) -> List[Tuple[int, Tuple[float, float, float]]]:
    translations: List[Tuple[int, Tuple[float, float, float]]] = []
    for line in lines:
        match = TRANSLATION_PATTERN.search(line)
        if not match:
            continue
        frame_idx = int(match.group(1)) if match.group(1) is not None else len(translations)
        coords = tuple(float(match.group(idx)) for idx in range(2, 5))  # type: ignore[misc]
        translations.append((frame_idx, coords))
    return translations


def detect_jumps(
    translations: Sequence[Tuple[int, Tuple[float, float, float]]], threshold: float
) -> List[Tuple[int, Tuple[float, float, float], float]]:
    jumps: List[Tuple[int, Tuple[float, float, float], float]] = []
    for idx in range(1, len(translations)):
        _, prev = translations[idx - 1]
        _, curr = translations[idx]
        delta = tuple(curr[axis] - prev[axis] for axis in range(3))
        max_delta = max(abs(component) for component in delta)
        if max_delta >= threshold:
            jumps.append((idx, delta, max_delta))
    return jumps


def print_context(
    translations: Sequence[Tuple[int, Tuple[float, float, float]]],
    jump_idx: int,
    delta: Tuple[float, float, float],
    max_delta: float,
    context: int,
) -> None:
    start = max(0, jump_idx - context)
    end = min(len(translations), jump_idx + context + 1)
    print(
        f"\nJump detected between entries {jump_idx - 1} and {jump_idx} "
        f"(max |delta|={max_delta:.3f}, delta={delta})"
    )
    for idx in range(start, end):
        frame_idx, coords = translations[idx]
        marker = "->" if idx in (jump_idx - 1, jump_idx) else "  "
        print(f"{marker} idx={idx:4d} frame={frame_idx:8d} translation={coords}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Extract camera translation values from ReShade.log and print a context "
            "window when large jumps between frames are detected."
        )
    )
    parser.add_argument(
        "--log-path",
        default=DEFAULT_LOG_PATH,
        help="Path to the ReShade.log file containing the translation log lines.",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=1.0,
        help=(
            "Minimum absolute per-axis delta to flag as a jump (units match the logged translations). "
            "Default is 1.0."
        ),
    )
    parser.add_argument(
        "--context",
        type=int,
        default=5,
        help="Number of logged frames to show before and after a detected jump (default: 5).",
    )
    args = parser.parse_args()

    log_path = Path(args.log_path)
    if not log_path.is_file():
        print(f"Log file not found: {log_path}")
        return

    lines = log_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    translations = parse_translations(lines)
    if not translations:
        print("No translation entries were found in the log.")
        return

    print(f"Found {len(translations)} translation entries in {log_path}.")

    jumps = detect_jumps(translations, args.threshold)
    if not jumps:
        print("No jumps exceeded the configured threshold.")
        return

    for jump_idx, delta, max_delta in jumps:
        print_context(translations, jump_idx, delta, max_delta, args.context)


if __name__ == "__main__":
    main()
