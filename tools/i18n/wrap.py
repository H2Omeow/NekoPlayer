#!/usr/bin/env python3
"""Conservative wrapping codemod for NekoPlayer i18n.

Defaults to a dry-run. Only static strings in UI/error contexts are wrapped;
every batch must be compiled and reviewed afterwards.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from scan import Entry, scan, DEFAULT_WEB

ROOT = Path(__file__).resolve().parents[2]
WRAPPER_IMPORT = {
    "android": "import top.nekoh2o.player.i18n.NekoI18n.tr",
    "flutter": "import 'package:nekoplayer/i18n/tr.dart';",
    "web": None,
}
LOG_PATTERNS = re.compile(
    r"(Log\.[vdiew]|android\.util\.Log|debugPrint|\bprint\s*\(|console\.(log|warn|error|debug)|CrashLog|Timber)"
)
LOGIC_PATTERNS = re.compile(
    r"(==|!=|\.equals\s*\(|\.contains\s*\(|\.startsWith\s*\(|\.endsWith\s*\()"
)
KEY_PATTERNS = re.compile(
    r"(putString|getString|getBoolean|getInt|getFloat|putExtra|getStringExtra|Uri\.parse|"
    r"SharedPreferences|to\s*\"|->\s*$|const val|private const|enum class|companion object)"
)
SKIP_DIRS = {
    "/data/model/",
    "/test/",
}
# Android/Dart strings that are data rather than UI should be translated at the
# render site so they react to a language change.
DATA_FILES = {
    "app/src/main/java/top/nekoh2o/player/data/model/AudioEffectModels.kt",
    "app/src/main/java/top/nekoh2o/player/data/model/MasteringPresets.kt",
    "app/src/main/java/top/nekoh2o/player/data/model/Models.kt",
    # Flutter data labels are translated by getters at the render site.
    "desktop_flutter/lib/domain/audio_effects.dart",
    "desktop_flutter/lib/domain/comments.dart",
    "desktop_flutter/lib/domain/mastering_presets.dart",
    "desktop_flutter/lib/domain/online_music.dart",
    "desktop_flutter/lib/sync/sync_section.dart",
    "desktop_flutter/lib/ui/shell/destinations.dart",
}
FLUTTER_SKIP_DIRS = (
    "desktop_flutter/lib/i18n/",
    "desktop_flutter/test/",
)


def should_wrap(entry: Entry) -> bool:
    if entry.kind not in {"ui", "error"} or entry.dynamic or entry.wrapped:
        return False
    rel = entry.file
    root = str(ROOT) + "/"
    if rel.startswith(root):
        rel = rel[len(root):]
    if entry.text.startswith("http") or entry.text.startswith("/"):
        return False
    if "\n" in entry.text:
        return False
    if any(skip in rel for skip in SKIP_DIRS):
        return False
    if any(rel.startswith(skip) for skip in FLUTTER_SKIP_DIRS):
        return False
    if rel in DATA_FILES:
        return False
    line = entry.line_text
    if LOG_PATTERNS.search(line) or LOGIC_PATTERNS.search(line) or KEY_PATTERNS.search(line):
        return False
    # Do not touch strings in annotation arguments or map keys.
    before = line.split(entry.text, 1)[0] if entry.text in line else ""
    if before.rstrip().endswith("@"):
        return False
    return True


def wrap_file(path: Path, entries: list[Entry], platform: str, apply: bool) -> tuple[int, str | None]:
    text = path.read_text(encoding="utf-8")
    selected = [entry for entry in entries if should_wrap(entry)]
    if not selected:
        return 0, None
    replacements = sorted(selected, key=lambda entry: entry.start, reverse=True)
    for entry in replacements:
        raw = text[entry.start:entry.end]
        text = text[:entry.start] + f"tr({raw})" + text[entry.end:]
    imp = WRAPPER_IMPORT[platform]
    if imp and imp not in text:
        match = re.search(r"^package .+$", text, re.MULTILINE)
        if match:
            text = text[:match.end()] + "\n\n" + imp + text[match.end():]
        else:
            text = imp + "\n" + text
    if apply:
        path.write_text(text, encoding="utf-8")
    return len(replacements), text


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=["android", "flutter", "web"], required=True)
    parser.add_argument("--files", nargs="*", type=Path)
    parser.add_argument("--web-root", type=Path, default=DEFAULT_WEB)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()

    entries = scan(args.platform, args.web_root)
    by_file: dict[str, list[Entry]] = {}
    for entry in entries:
        by_file.setdefault(entry.file, []).append(entry)

    selected_files = args.files
    if selected_files:
        selected_files = [path.resolve() for path in selected_files]
    else:
        selected_files = [Path(path) for path in by_file]

    report = []
    total = 0
    for path in selected_files:
        if not path.is_absolute():
            path = (ROOT / path) if str(path).startswith("app/") or str(path).startswith("desktop_flutter/") else path
        if not path.exists():
            print(f"missing {path}", file=sys.stderr)
            continue
        key = str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)
        count, preview = wrap_file(path, by_file.get(key, []), args.platform, args.apply)
        total += count
        report.append({"file": key, "count": count})
        if count and preview is not None and not args.apply:
            print(f"would wrap {count}: {key}")
    if args.json:
        args.json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(("wrapped " if args.apply else "would wrap ") + f"{total} strings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
