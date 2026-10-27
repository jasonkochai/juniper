#!/usr/bin/env python3
"""Fill the {{PLACEHOLDERS}} in nas/ from juniper.local.env into build/nas/."""
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "nas"
SCRIPTS = ROOT / "scripts"
OUT = ROOT / "build" / "nas"
PLACEHOLDER = re.compile(r"\{\{([A-Z0-9_]+)\}\}")


def load_env(path: Path) -> dict[str, str]:
    """Read KEY=VALUE lines, skipping comments and empty values."""
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip().strip("\"'")
        if value:
            values[key.strip()] = value
    return values


def render(text: str, values: dict[str, str]) -> tuple[str, set[str]]:
    """Return the filled text and the placeholder names that had no value."""
    missing = {k for k in PLACEHOLDER.findall(text) if k not in values}
    filled = PLACEHOLDER.sub(
        lambda m: values.get(m.group(1), m.group(0)), text)
    return filled, missing


def main() -> int:
    """Render every template and report files that still miss values."""
    default = ROOT / "juniper.local.env"
    env_file = Path(sys.argv[1]) if len(sys.argv) > 1 else default
    if not env_file.exists():
        print(f"missing {env_file}: copy juniper.env.example and fill it in")
        return 1
    values = load_env(env_file)
    if OUT.exists():
        shutil.rmtree(OUT)
    skipped: dict[str, set[str]] = {}
    for src in sorted(SRC.rglob("*")):
        if src.is_dir():
            continue
        rel = src.relative_to(SRC)
        filled, missing = render(src.read_text(), values)
        if missing:
            skipped[str(rel)] = missing
            continue
        dest = OUT / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(filled)
    for script in ("nas.sh", "merge_config.py"):
        shutil.copy2(SCRIPTS / script, OUT / script)
    print(f"rendered into {OUT.relative_to(ROOT)}/")
    for name, missing in skipped.items():
        print(f"  skipped {name}: no value for {', '.join(sorted(missing))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
