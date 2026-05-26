"""
Phase 5 helper: slice the position-icons and modifier-icons grid PNGs into
individual files for use as atlas entries.

Run once from the project root after running fetch_deps.py:
    python .claude/skills/defold-project-setup/scripts/slice_icon_grids.py

Outputs to assets/images/ui/icons/. Re-running overwrites the files.
"""

from __future__ import annotations

import sys
from pathlib import Path
from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[4]

POSITION_GRID = PROJECT_ROOT / "assets" / "images" / "ui" / "28_position_icons_grid.png"
MODIFIER_GRID = PROJECT_ROOT / "assets" / "images" / "ui" / "29_modifier_icons_grid.png"
OUTPUT_DIR = PROJECT_ROOT / "assets" / "images" / "ui" / "icons"

# Row-major layout per the Phase 5 prompt.
POSITION_LAYOUT = {
    "cols": 4,
    "rows": 3,
    "names": [
        "qb", "rb", "wr", "te",
        "ol", "k",  "cb", "s",
        "lb", "de", "dt", "st",
    ],
}

MODIFIER_LAYOUT = {
    "cols": 5,
    "rows": 4,
    "names": [
        "homeTurf",   "muddyField",  "windTunnel",  "frozenTundra", "blindingSun",
        "redZone",    "hurryUp",     "preventD",    "scouted",      "blitzZone",
        "scramble",   "groundPound", "airRaid",     "trenches",     "secondary",
        "specialUnit","coinFlip",    "turnover",    "suddenDeath",  "playOfGame",
    ],
}


def slice_grid(grid_path: Path, layout: dict, prefix: str) -> int:
    if not grid_path.exists():
        print(f"  MISSING: {grid_path}")
        return 0

    img = Image.open(grid_path).convert("RGBA")
    cols, rows = layout["cols"], layout["rows"]
    names = layout["names"]
    expected = cols * rows
    if len(names) != expected:
        print(f"  ERROR: {grid_path.name} expects {expected} names, got {len(names)}")
        return 0

    tile_w = img.width // cols
    tile_h = img.height // rows
    print(f"  {grid_path.name}: {img.size} -> {cols}x{rows} tiles of {tile_w}x{tile_h}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    written = 0
    for idx, name in enumerate(names):
        row = idx // cols
        col = idx % cols
        left = col * tile_w
        upper = row * tile_h
        right = left + tile_w
        lower = upper + tile_h
        tile = img.crop((left, upper, right, lower))
        out_path = OUTPUT_DIR / f"{prefix}_{name}.png"
        tile.save(out_path, "PNG")
        written += 1
    return written


def main() -> int:
    print(f"Project root: {PROJECT_ROOT}")
    print(f"Output dir:   {OUTPUT_DIR}")
    print()
    print("== Position icons ==")
    pos_count = slice_grid(POSITION_GRID, POSITION_LAYOUT, "pos")
    print()
    print("== Modifier icons ==")
    mod_count = slice_grid(MODIFIER_GRID, MODIFIER_LAYOUT, "mod")
    print()
    print(f"Sliced {pos_count} position icons and {mod_count} modifier icons.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
