#!/usr/bin/env python3
"""Merge a Juniper openclaw.json template into the live config."""
import json
import sys
from typing import Any

# Blocks OpenClaw writes itself; the live copy wins (docs/setup.md, step 1.6).
OPENCLAW_OWNED = ("plugins", "skills", "meta", "wizard", "talk")


def merge(live: dict[str, Any], template: dict[str, Any]) -> dict[str, Any]:
    """Return the template plus every block only the live config has."""
    merged = dict(template)
    for key, value in live.items():
        if key in ("plugins", "skills") and key in template:
            entries = {**template[key].get("entries", {}),
                       **value.get("entries", {})}
            merged[key] = {**template[key], **value, "entries": entries}
        elif key not in template or key in OPENCLAW_OWNED:
            merged[key] = value
    return merged


def main() -> int:
    """Print the merged config for LIVE and TEMPLATE paths."""
    if len(sys.argv) != 3:
        print("usage: merge_config.py LIVE.json TEMPLATE.json",
              file=sys.stderr)
        return 2
    with open(sys.argv[2]) as f:
        template = json.load(f)
    try:
        with open(sys.argv[1]) as f:
            live = json.load(f)
    except FileNotFoundError:
        live = {}
    json.dump(merge(live, template), sys.stdout, indent=2, ensure_ascii=False)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
