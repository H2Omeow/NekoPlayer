#!/usr/bin/env python3
"""Wrap browser-side Chinese UI literals with the shared tr() runtime."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
from scan import scan, DEFAULT_WEB  # noqa: E402

LOGIC = re.compile(r"(===|!==|==|!=|\.includes\s*\(|\.indexOf\s*\(|\.startsWith\s*\(|\.endsWith\s*\()")
SKIP_LINE = re.compile(r"(console\.|localStorage|sessionStorage|data-i18n|import\s|export\s|\.env|URL\()")
SKIP_FILES = {"src/js/i18n.js", "server.js", "social.mjs", "site-comments.mjs", "server-i18n.mjs"}


def should_wrap(entry) -> bool:
    if entry.kind not in {"ui", "error"} or entry.dynamic or entry.wrapped:
        return False
    rel = entry.file
    root = str(ROOT) + "/"
    if rel.startswith(root):
        rel = rel[len(root):]
    if not rel.endswith(".js") or rel in SKIP_FILES:
        return False
    line = entry.line_text.strip()
    if LOGIC.search(line) or SKIP_LINE.search(line):
        return False
    text = entry.text
    if not text.strip() or "\n" in text or "\t" in text:
        return False
    if text.startswith(("http", "/", ".", "#", "@")):
        return False
    # Object keys and CSS/HTML-ish payloads are not UI copy.
    if "<" in text and ">" in text:
        return False
    before = line.split(text, 1)[0] if text in line else ""
    if before.rstrip().endswith(("@", "case", "key:")):
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    entries = [entry for entry in scan("web", DEFAULT_WEB) if should_wrap(entry)]
    by_file: dict[str, list] = {}
    for entry in entries:
        by_file.setdefault(entry.file, []).append(entry)
    total = 0
    for file, items in sorted(by_file.items()):
        path = Path(file)
        text = path.read_text(encoding="utf-8")
        for entry in sorted(items, key=lambda item: item.start, reverse=True):
            raw = text[entry.start:entry.end]
            text = text[:entry.start] + f"tr({raw})" + text[entry.end:]
            total += 1
        rel = path.relative_to(DEFAULT_WEB)
        if str(rel).startswith("src/js/") and str(rel) != "src/js/i18n.js":
            imp = "import { tr } from './i18n.js';"
            if imp not in text:
                # Keep the leading comment banner when present.
                text = imp + "\n" + text
        if args.apply:
            path.write_text(text, encoding="utf-8")
        print(f"{'wrapped' if args.apply else 'would wrap'} {len(items)}: {rel}")
    print(f"{'wrapped' if args.apply else 'would wrap'} {total} strings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
