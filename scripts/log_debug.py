#!/usr/bin/env python3
"""
log-debug.py — Append a raw debug entry to JOURNAL.md

Usage:
    python log-debug.py                  # uses ./JOURNAL.md
    python log-debug.py --file path.md   # use a different journal file
"""

import argparse
import os
import re
import sys
from datetime import date
from pathlib import Path


def prompt(label, hint=""):
    """
    Prompt for a single-line input. Uses input()'s built-in prompt
    argument, which forces the prompt to appear before reading.
    """
    if hint:
        text = f"\n>>> {label}\n    ({hint})\n> "
    else:
        text = f"\n>>> {label}\n> "
    try:
        return input(text).strip()
    except EOFError:
        return ""


def prompt_multiline(label, hint=""):
    """
    Read multiple lines. First line prompt uses input() so it always shows.
    Subsequent lines have simpler continuation prompt.
    Ends when an empty line is entered.
    """
    if hint:
        first_prompt = f"\n>>> {label}\n    ({hint})\n    (blank line to finish)\n> "
    else:
        first_prompt = f"\n>>> {label}\n    (blank line to finish)\n> "

    lines = []
    try:
        first = input(first_prompt)
    except EOFError:
        return ""

    if first == "":
        return ""
    lines.append(first)

    while True:
        try:
            line = input("> ")
        except EOFError:
            break
        if line == "":
            break
        lines.append(line)
    return "\n".join(lines)


def build_entry(title, fields):
    """Build the markdown entry string."""
    today = date.today().isoformat()
    placeholder = "_not recorded_"

    def val(name):
        return fields.get(name) or placeholder

    return f"""
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


DATED_ENTRY_RE = re.compile(r"^## 20\d{2}-\d{2}-\d{2}", re.MULTILINE)


def insert_entry(journal_path, new_entry):
    """Insert entry at top (before first existing dated entry) or append to end."""
    content = journal_path.read_text(encoding="utf-8")
    match = DATED_ENTRY_RE.search(content)
    if match:
        insertion_point = match.start()
        new_content = (
            content[:insertion_point]
            + new_entry.lstrip()
            + "\n"
            + content[insertion_point:]
        )
    else:
        if not content.endswith("\n"):
            content += "\n"
        new_content = content + new_entry
    journal_path.write_text(new_content, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(
        description="Append a debug entry to your engineering journal."
    )
    parser.add_argument(
        "--file", "-f",
        default=os.environ.get("JOURNAL_PATH", "JOURNAL.md"),
        help="Path to the journal file (default: ./JOURNAL.md)"
    )
    args = parser.parse_args()

    journal_path = Path(args.file)

    if not journal_path.is_file():
        print(f"ERROR: Journal not found at {journal_path}")
        print("Run this from your repo root, or pass --file /path/to/JOURNAL.md")
        return 1

    print("===================================")
    print(f"  Log a debug entry to {journal_path.name}")
    print("===================================")
    print("Answer each prompt. Leave blank to skip.")

    # Title (single line, required)
    title = prompt("Short title", "e.g. 'Karpenter GPU node stuck in Pending'")
    if not title:
        print("Title is required. Aborting.")
        return 1

    # Five multi-line fields
    try:
        fields = {
            "context":    prompt_multiline("Context",    "What were you trying to do?"),
            "symptom":    prompt_multiline("Symptom",    "Paste the exact error or unexpected behavior"),
            "hypothesis": prompt_multiline("Hypothesis", "What did you think was wrong first?"),
            "root_cause": prompt_multiline("Root cause", "What was actually wrong?"),
            "fix":        prompt_multiline("Fix",        "Exact commands or config changes that worked"),
            "lesson":     prompt_multiline("Lesson",     "What will you do differently next time?"),
        }
    except KeyboardInterrupt:
        print("\nCancelled. No entry saved.")
        return 1

    # Build and write
    entry = build_entry(title, fields)
    try:
        insert_entry(journal_path, entry)
    except Exception as e:
        print(f"ERROR: Failed to write journal: {e}")
        return 1

    # Confirmation
    print()
    print("===================================")
    print(f"  Entry saved to {journal_path}")
    print("===================================")
    print()
    print("Next step (copy-paste to commit):")
    print(f"  git add {journal_path}")
    print(f'  git commit -m "docs(journal): {title}"')
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
