#!/usr/bin/env python3
"""
log-debug.py — Append a raw debug entry to JOURNAL.md

Usage:
    python log-debug.py                  # uses ./JOURNAL.md
    python log-debug.py --file path.md   # use a different journal file

Prompts for the 5 things worth capturing about a debug session.
Keeps entries raw and unpolished — the point is speed, not prose.

Tips:
    - For multi-line input (like a stack trace), paste all lines,
      then press Enter on an empty line to move to the next field
    - Any field can be left blank by pressing Enter without typing
    - New entries are inserted at the top of the journal (newest first)
"""

import argparse
import os
import re
import sys
from datetime import date
from pathlib import Path

# ---------------------------------------------------------------------------
# Terminal colors — only used if stdout is a TTY (not piped)
# ---------------------------------------------------------------------------
def supports_color() -> bool:
    """Return True if the terminal supports ANSI colors."""
    if not sys.stdout.isatty():
        return False
    if os.name == "nt":
        # Windows 10+ supports ANSI in modern terminals
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32
            kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)
            return True
        except Exception:
            return False
    return True

USE_COLOR = supports_color()

def c(code: str) -> str:
    """Return ANSI code if colors supported, else empty string."""
    return code if USE_COLOR else ""

BOLD  = c("\033[1m")
DIM   = c("\033[2m")
GREEN = c("\033[32m")
YELLOW = c("\033[33m")
RED   = c("\033[31m")
RESET = c("\033[0m")


# ---------------------------------------------------------------------------
# Prompting helpers
# ---------------------------------------------------------------------------
def read_field(label: str, hint: str) -> str:
    """
    Read a multi-line answer from stdin.
    Stops reading when the user enters an empty line.
    Returns the joined lines (or empty string if skipped).
    """
    print(file=sys.stderr)
    print(f"{BOLD}{label}{RESET} {DIM}{hint}{RESET}", file=sys.stderr)
    print(f"{DIM}(one or more lines; press Enter on an empty line to finish){RESET}",
          file=sys.stderr)

    lines = []
    while True:
        try:
            line = input()
        except EOFError:
            break
        if line == "":
            break
        lines.append(line)
    return "\n".join(lines)


def read_title() -> str:
    """Read a single-line title. Required."""
    print(file=sys.stderr)
    print(f"{BOLD}Short title{RESET} "
          f"{DIM}(e.g. 'Karpenter GPU node stuck in Pending'){RESET}",
          file=sys.stderr)
    try:
        title = input().strip()
    except EOFError:
        title = ""
    return title


# ---------------------------------------------------------------------------
# Entry construction
# ---------------------------------------------------------------------------
def build_entry(title: str, fields: dict) -> str:
    """Build the markdown entry string."""
    today = date.today().isoformat()
    placeholder = "_not recorded_"

    def val(name: str) -> str:
        return fields.get(name) or placeholder

    entry = f"""
## {today} — {title}

**Context:** {val('context')}

**Symptom:**
```
{val('symptom')}
```

**Hypothesis:** {val('hypothesis')}

**Root cause:** {val('root_cause')}

**Fix:**
```
{val('fix')}
```

**Lesson:** {val('lesson')}

---
"""
    return entry


# ---------------------------------------------------------------------------
# Insertion logic
# ---------------------------------------------------------------------------
DATED_ENTRY_RE = re.compile(r"^## 20\d{2}-\d{2}-\d{2}", re.MULTILINE)

def insert_entry(journal_path: Path, new_entry: str) -> None:
    """
    Insert the new entry into the journal.

    Strategy:
      - If the journal has any existing dated entry (## YYYY-MM-DD ...),
        insert BEFORE the first one → newest at top.
      - Otherwise, append at the end.
    """
    content = journal_path.read_text(encoding="utf-8")

    match = DATED_ENTRY_RE.search(content)
    if match:
        # Insert new entry before first existing dated entry
        insertion_point = match.start()
        new_content = content[:insertion_point] + new_entry.lstrip() + "\n" + content[insertion_point:]
    else:
        # No existing entries — append to end
        if not content.endswith("\n"):
            content += "\n"
        new_content = content + new_entry

    journal_path.write_text(new_content, encoding="utf-8")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(
        description="Append a debug entry to your engineering journal."
    )
    parser.add_argument(
        "--file", "-f",
        default=os.environ.get("JOURNAL_PATH", "JOURNAL.md"),
        help="Path to the journal file (default: ./JOURNAL.md or $JOURNAL_PATH)"
    )
    args = parser.parse_args()

    journal_path = Path(args.file)

    # Sanity check
    if not journal_path.is_file():
        print(f"{YELLOW}Journal not found at: {journal_path}{RESET}", file=sys.stderr)
        print(f"Run from your repo root, or pass --file /path/to/JOURNAL.md",
              file=sys.stderr)
        return 1

    # Header
    print(file=sys.stderr)
    print(f"{BOLD}==================================={RESET}", file=sys.stderr)
    print(f"{BOLD}  Log a debug entry to {journal_path.name}{RESET}", file=sys.stderr)
    print(f"{BOLD}==================================={RESET}", file=sys.stderr)
    print(f"{DIM}Type your answer; press Enter on an empty line to move on.{RESET}",
          file=sys.stderr)
    print(f"{DIM}Leave any field blank to skip it.{RESET}", file=sys.stderr)

    # Title (required)
    title = read_title()
    if not title:
        print(f"{YELLOW}Title is required. Aborting.{RESET}", file=sys.stderr)
        return 1

    # The five fields
    try:
        fields = {
            "context":    read_field("Context",      "What were you trying to do?"),
            "symptom":    read_field("Symptom",      "Paste the exact error or unexpected behavior"),
            "hypothesis": read_field("Hypothesis",   "What did you think was wrong first?"),
            "root_cause": read_field("Root cause",   "What was actually wrong?"),
            "fix":        read_field("Fix",          "Exact commands or config changes that worked"),
            "lesson":     read_field("Lesson",       "What will you do differently next time?"),
        }
    except KeyboardInterrupt:
        print(f"\n{YELLOW}Cancelled. No entry saved.{RESET}", file=sys.stderr)
        return 1

    # Build and insert
    entry = build_entry(title, fields)
    try:
        insert_entry(journal_path, entry)
    except Exception as e:
        print(f"{RED}Failed to write journal: {e}{RESET}", file=sys.stderr)
        return 1

    # Confirmation
    print(file=sys.stderr)
    print(f"{GREEN}Entry saved to {journal_path}{RESET}", file=sys.stderr)
    print(file=sys.stderr)
    print(f"{DIM}Next step (copy-paste this to commit):{RESET}", file=sys.stderr)
    print(f"  git add {journal_path}", file=sys.stderr)
    print(f'  git commit -m "docs(journal): {title}"', file=sys.stderr)
    print(file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
