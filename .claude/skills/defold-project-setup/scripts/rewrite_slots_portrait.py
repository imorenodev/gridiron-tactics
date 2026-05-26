"""
Phase 5.5.4 helper: rewrite the 30 horizontal-bar slot blocks in
main/ui/hud.gui as portrait-card hierarchies. Each old slot (root +
single text child) becomes a new slot with root + 7 children:
  - root              (140x200, dark "card back" color)
  - <slot>_frame      (sprite, card frame texture, enabled=false default)
  - <slot>_portrait   (sprite, default QB portrait, enabled=false default)
  - <slot>_pos_icon   (sprite, default QB icon, enabled=false default)
  - <slot>_ability_star (sprite, star_ability, enabled=false default)
  - <slot>_cost       (text, top-center)
  - <slot>_name       (text, bottom-center, line_break)
  - <slot>_stat       (text, below name)

Positions follow the Phase 5.5.4 spec (vertical column, 220px stride).
At runtime, hud_render.compute_stack_position overrides positions for
the fan layout (Phase 5.5.5).

Run once after the prompt drop:
    python .claude/skills/defold-project-setup/scripts/rewrite_slots_portrait.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[4]
GUI_FILE = PROJECT_ROOT / "main" / "ui" / "hud.gui"


SLOT_SIZE_W = 140.0
SLOT_SIZE_H = 200.0


def slot_y_relative(side: str, slot_idx: int) -> float:
    """Phase 5.5.4 vertical column positions (lane-center-relative)."""
    lane_center_y = 1500.0
    if side == "ai":
        design_y = 2100.0 - slot_idx * 220.0
    else:
        design_y = 800.0 + slot_idx * 220.0
    return design_y - lane_center_y


def generate_slot_block(lane_idx: int, side: str, slot_idx: int) -> str:
    """Generate the 8 GUI node blocks for one portrait slot."""
    side_prefix = "p" if side == "you" else "ai"
    slot_id = f"lane_{lane_idx}_{side_prefix}_slot_{slot_idx}"
    parent_id = f"lane_{lane_idx}_root"
    y = slot_y_relative(side, slot_idx)

    return f"""nodes {{
  position {{ x: 0.0 y: {y:.1f} z: 0.0 }}
  size {{ x: {SLOT_SIZE_W:.1f} y: {SLOT_SIZE_H:.1f} z: 0.0 }}
  color {{ x: 0.18 y: 0.18 z: 0.22 w: 1.0 }}
  type: TYPE_BOX
  id: "{slot_id}"
  parent: "{parent_id}"
  enabled: false
  inherit_alpha: true
}}
nodes {{
  position {{ x: 0.0 y: 0.0 z: 0.0 }}
  size {{ x: {SLOT_SIZE_W:.1f} y: {SLOT_SIZE_H:.1f} z: 0.0 }}
  color {{ x: 1.0 y: 1.0 z: 1.0 w: 1.0 }}
  type: TYPE_BOX
  texture: "cards/frame_common_off"
  id: "{slot_id}_frame"
  parent: "{slot_id}"
  enabled: false
  inherit_alpha: true
}}
nodes {{
  position {{ x: 0.0 y: 20.0 z: 0.0 }}
  size {{ x: 80.0 y: 80.0 z: 0.0 }}
  color {{ x: 1.0 y: 1.0 z: 1.0 w: 1.0 }}
  type: TYPE_BOX
  texture: "portraits/qb_black_navy"
  id: "{slot_id}_portrait"
  parent: "{slot_id}"
  enabled: false
  inherit_alpha: true
}}
nodes {{
  position {{ x: 52.0 y: 80.0 z: 0.0 }}
  size {{ x: 28.0 y: 28.0 z: 0.0 }}
  color {{ x: 1.0 y: 1.0 z: 1.0 w: 1.0 }}
  type: TYPE_BOX
  texture: "icons/pos_qb"
  id: "{slot_id}_pos_icon"
  parent: "{slot_id}"
  enabled: false
  inherit_alpha: true
}}
nodes {{
  position {{ x: -52.0 y: 80.0 z: 0.0 }}
  size {{ x: 28.0 y: 28.0 z: 0.0 }}
  color {{ x: 1.0 y: 1.0 z: 1.0 w: 1.0 }}
  type: TYPE_BOX
  texture: "ui_chrome/star_ability"
  id: "{slot_id}_ability_star"
  parent: "{slot_id}"
  enabled: false
  inherit_alpha: true
}}
nodes {{
  position {{ x: 0.0 y: 80.0 z: 0.0 }}
  scale {{ x: 0.8 y: 0.8 z: 1.0 }}
  size {{ x: 40.0 y: 30.0 z: 0.0 }}
  color {{ x: 1.0 y: 0.85 z: 0.2 w: 1.0 }}
  type: TYPE_TEXT
  text: ""
  font: "default"
  id: "{slot_id}_cost"
  parent: "{slot_id}"
  inherit_alpha: true
}}
nodes {{
  position {{ x: 0.0 y: -50.0 z: 0.0 }}
  scale {{ x: 0.7 y: 0.7 z: 1.0 }}
  size {{ x: 130.0 y: 40.0 z: 0.0 }}
  color {{ x: 1.0 y: 1.0 z: 1.0 w: 1.0 }}
  type: TYPE_TEXT
  text: ""
  font: "default"
  id: "{slot_id}_name"
  parent: "{slot_id}"
  line_break: true
  inherit_alpha: true
}}
nodes {{
  position {{ x: 0.0 y: -85.0 z: 0.0 }}
  scale {{ x: 0.9 y: 0.9 z: 1.0 }}
  size {{ x: 130.0 y: 30.0 z: 0.0 }}
  color {{ x: 0.95 y: 0.5 z: 0.15 w: 1.0 }}
  type: TYPE_TEXT
  text: ""
  font: "default"
  id: "{slot_id}_stat"
  parent: "{slot_id}"
  inherit_alpha: true
}}"""


def split_blocks(content: str) -> list[tuple[str, str]]:
    """Split the file into ('nodes', block_text) and ('other', text) chunks.

    A 'nodes' block starts with a line that's exactly 'nodes {' and ends at
    the first line that's exactly '}' at the outer-brace level.
    """
    blocks: list[tuple[str, str]] = []
    lines = content.split("\n")
    current: list[str] = []
    in_nodes = False
    brace_depth = 0

    for line in lines:
        if not in_nodes:
            stripped = line.strip()
            if stripped == "nodes {":
                # Flush 'other' chunk.
                if current:
                    blocks.append(("other", "\n".join(current)))
                    current = []
                current.append(line)
                in_nodes = True
                brace_depth = 1
            else:
                current.append(line)
        else:
            current.append(line)
            for ch in line:
                if ch == "{":
                    brace_depth += 1
                elif ch == "}":
                    brace_depth -= 1
            if brace_depth == 0:
                blocks.append(("nodes", "\n".join(current)))
                current = []
                in_nodes = False

    if current:
        blocks.append(("other", "\n".join(current)))

    return blocks


SLOT_ID_PATTERN = re.compile(r'^\s*id:\s*"(lane_(\d+)_(p|ai)_slot_(\d+)(_text)?)"\s*$', re.MULTILINE)


def transform(content: str) -> str:
    out_chunks: list[str] = []
    replaced_count = 0
    removed_text_count = 0

    for kind, text in split_blocks(content):
        if kind != "nodes":
            out_chunks.append(text)
            continue

        m = SLOT_ID_PATTERN.search(text)
        if not m:
            out_chunks.append(text)
            continue

        lane_idx = int(m.group(2))
        side_short = m.group(3)
        slot_idx = int(m.group(4))
        is_text = m.group(5) is not None

        if is_text:
            # Drop old "_text" blocks; the new portrait slot has separate
            # cost/name/stat text children.
            removed_text_count += 1
            continue

        side = "ai" if side_short == "ai" else "you"
        new_block = generate_slot_block(lane_idx, side, slot_idx)
        out_chunks.append(new_block)
        replaced_count += 1

    print(f"Replaced {replaced_count} slot-root blocks, dropped {removed_text_count} legacy text blocks.")
    return "\n".join(out_chunks)


def main() -> int:
    if not GUI_FILE.exists():
        print(f"MISSING: {GUI_FILE}", file=sys.stderr)
        return 1
    content = GUI_FILE.read_text(encoding="utf-8")
    new_content = transform(content)
    GUI_FILE.write_text(new_content, encoding="utf-8")
    print(f"Wrote {GUI_FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
