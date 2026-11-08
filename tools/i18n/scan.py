#!/usr/bin/env python3
"""Extract and audit user-facing Chinese strings for NekoPlayer i18n.

This is a lexical scanner, not a compiler. It deliberately errs on the side of
reporting too much; every automated rewrite must still be reviewed and built.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "i18n" / "catalog.json"
DEFAULT_WEB = Path("/www/wwwroot/superplayer")
CJK = re.compile(r"[㐀-鿿]")
LOG_CONTEXT = re.compile(
    r"\b(Log\.[vdiew]|android\.util\.Log|debugPrint|print|console\.(log|warn|error|debug)|CrashLog|Timber)\b"
)
TECHNICAL = re.compile(
    r"^(https?://|/|GET|POST|PUT|DELETE|PATCH|Bearer |application/|text/|image/|audio/)"
)
TECHNICAL_WORDS = {
    "zh-CN", "zh-TW", "en", "ja", "UTF-8", "GET", "POST", "PUT", "DELETE",
    "netease", "kugou", "kuwo", "qq", "migu", "bilibili", "song", "playlist",
    "user", "share", "chat", "system", "light", "dark", "auto",
}
WRAPPER_BEFORE = re.compile(r"(?:\btr|\bt|\b_tr)\s*\(\s*$")


@dataclass
class Entry:
    platform: str
    file: str
    line: int
    column: int
    text: str
    start: int
    end: int
    dynamic: bool
    wrapped: bool
    kind: str
    line_text: str


def is_cjk(value: str) -> bool:
    return bool(CJK.search(value))


def line_of(text: str, offset: int) -> tuple[int, str]:
    line = text.count("\n", 0, offset) + 1
    start = text.rfind("\n", 0, offset) + 1
    end = text.find("\n", offset)
    if end < 0:
        end = len(text)
    return line, text[start:end].strip()


def classify(line_text: str, value: str, path: Path, dynamic: bool) -> str:
    if "/test/" in str(path) or path.name.endswith("Test.kt") or path.name.endswith("_test.dart"):
        return "test"
    if LOG_CONTEXT.search(line_text):
        return "log"
    if value in TECHNICAL_WORDS or TECHNICAL.search(value):
        return "technical"
    if dynamic:
        return "dynamic"
    if re.search(r"(?:\bthrow\b|\bError\b|\bException\b|toast|Toast|snackbar|SnackBar|msg\b)", line_text):
        return "error"
    return "ui"


def preceded_by_wrapper(text: str, start: int) -> bool:
    return bool(WRAPPER_BEFORE.search(text[max(0, start - 24):start]))


def scan_quoted(text: str, quotes: str) -> list[tuple[int, int, str, bool]]:
    """Return (offset, content, dynamic) for quoted literals.

    Handles escapes and ${...}/$identifier interpolation. Triple-quoted strings
    are handled by passing a three-character quote marker.
    """
    out: list[tuple[int, int, str, bool]] = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i + 2)
            i = n if j < 0 else j + 1
            continue
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        matched = None
        for q in quotes:
            if text.startswith(q, i):
                matched = q
                break
        if matched is None:
            i += 1
            continue
        start = i
        i += len(matched)
        buf: list[str] = []
        dynamic = False
        while i < n:
            if text.startswith(matched, i):
                i += len(matched)
                break
            ch = text[i]
            if ch == "\\" and i + 1 < n:
                buf.append(text[i:i + 2])
                i += 2
                continue
            if ch == "$" and len(matched) < 3:
                # Dart/JS/Kotlin interpolation. Kotlin uses ${...}; Dart also $name.
                dynamic = True
                if i + 1 < n and text[i + 1] == "{":
                    depth = 1
                    j = i + 2
                    while j < n and depth:
                        if text[j] == "{":
                            depth += 1
                        elif text[j] == "}":
                            depth -= 1
                        j += 1
                    buf.append(text[i:j])
                    i = j
                    continue
                j = i + 1
                while j < n and (text[j].isalnum() or text[j] in "_."):
                    j += 1
                buf.append(text[i:j])
                i = j
                continue
            buf.append(ch)
            i += 1
        out.append((start, i, "".join(buf), dynamic))
    return out


def scan_kotlin(text: str, path: Path) -> list[Entry]:
    entries: list[Entry] = []
    for offset, end, value, dynamic in scan_quoted(text, ['"""', '"']):
        if not is_cjk(value):
            continue
        line, line_text = line_of(text, offset)
        entries.append(
            Entry(
                "android",
                str(path.relative_to(ROOT)),
                line,
                offset - text.rfind("\n", 0, offset),
                value,
                offset,
                end,
                dynamic,
                preceded_by_wrapper(text, offset),
                classify(line_text, value, path, dynamic),
                line_text,
            )
        )
    return entries


def scan_dart(text: str, path: Path) -> list[Entry]:
    entries: list[Entry] = []
    # Dart raw strings (r'...', r"...") do not interpolate; detect the prefix and
    # blank it out so $ is treated literally.
    raw_positions = {
        m.start() + 1 for m in re.finditer(r"\br(['\"])", text)
    }
    for offset, end, value, dynamic in scan_quoted(text, ["'''", '"""', "'", '"']):
        if not is_cjk(value):
            continue
        if offset in raw_positions:
            dynamic = False
        line, line_text = line_of(text, offset)
        entries.append(
            Entry(
                "flutter",
                str(path.relative_to(ROOT)),
                line,
                offset - text.rfind("\n", 0, offset),
                value,
                offset,
                end,
                dynamic,
                preceded_by_wrapper(text, offset),
                classify(line_text, value, path, dynamic),
                line_text,
            )
        )
    return entries


def scan_js(text: str, path: Path) -> list[Entry]:
    entries: list[Entry] = []
    for offset, end, value, dynamic in scan_quoted(text, ["`", "'", '"']):
        if not is_cjk(value):
            continue
        line, line_text = line_of(text, offset)
        entries.append(
            Entry(
                "web",
                str(path),
                line,
                offset - text.rfind("\n", 0, offset),
                value,
                offset,
                end,
                dynamic,
                preceded_by_wrapper(text, offset),
                classify(line_text, value, path, dynamic),
                line_text,
            )
        )
    return entries


def scan_html(text: str, path: Path) -> list[Entry]:
    entries: list[Entry] = []
    # Strip comments and script/style bodies before scanning text/attribute values.
    cleaned = re.sub(r"<!--.*?-->", lambda m: " " * len(m.group(0)), text, flags=re.S)
    cleaned = re.sub(r"<(script|style)\b.*?</\1>", lambda m: " " * len(m.group(0)), cleaned, flags=re.S | re.I)
    for match in re.finditer(r">([^<>]+)<|([\"'])([^\"']*[㐀-鿿][^\"']*)\2", cleaned):
        value = match.group(1) or match.group(3) or ""
        value = value.strip()
        if not is_cjk(value):
            continue
        offset = match.start(1) if match.group(1) is not None else match.start(3)
        line, line_text = line_of(text, offset)
        entries.append(
            Entry(
                "web",
                str(path),
                line,
                offset - text.rfind("\n", 0, offset),
                value,
                offset,
                offset + len(value),
                False,
                "data-i18n" in line_text,
                classify(line_text, value, path, False),
                line_text,
            )
        )
    return entries


def files_for(platform: str, web: Path) -> list[Path]:
    if platform == "android":
        return sorted((ROOT / "app/src/main/java").rglob("*.kt"))
    if platform == "flutter":
        return sorted((ROOT / "desktop_flutter/lib").rglob("*.dart"))
    result: list[Path] = []
    for name in ("index.html", "share.html", "server.js", "social.mjs", "site-comments.mjs"):
        path = web / name
        if path.exists():
            result.append(path)
    for pattern in ("src/*.js", "src/js/*.js"):
        result.extend(sorted(web.glob(pattern)))
    return result


def scan(platform: str, web: Path) -> list[Entry]:
    result: list[Entry] = []
    for path in files_for(platform, web):
        text = path.read_text(encoding="utf-8")
        suffix = path.suffix.lower()
        if suffix == ".kt":
            result.extend(scan_kotlin(text, path))
        elif suffix == ".dart":
            result.extend(scan_dart(text, path))
        elif suffix == ".js":
            result.extend(scan_js(text, path))
        elif suffix == ".html":
            result.extend(scan_html(text, path))
    return result


def load_catalog() -> dict[str, dict]:
    if not CATALOG.exists():
        return {}
    data = json.loads(CATALOG.read_text(encoding="utf-8"))
    return data.get("messages", {})


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=["android", "flutter", "web", "all"], default="all")
    parser.add_argument("--web", type=Path, default=DEFAULT_WEB)
    parser.add_argument("--json", type=Path, help="write entries to this file")
    parser.add_argument("--summary", action="store_true")
    parser.add_argument("--check", action="store_true", help="fail on UI strings missing from the catalog")
    args = parser.parse_args()

    platforms = ["android", "flutter", "web"] if args.platform == "all" else [args.platform]
    entries: list[Entry] = []
    for platform in platforms:
        entries.extend(scan(platform, args.web))

    if args.json:
        args.json.write_text(
            json.dumps([asdict(entry) for entry in entries], ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    if args.summary:
        by_platform: dict[str, int] = {}
        by_kind: dict[str, int] = {}
        unique: set[tuple[str, str]] = set()
        for entry in entries:
            by_platform[entry.platform] = by_platform.get(entry.platform, 0) + 1
            by_kind[entry.kind] = by_kind.get(entry.kind, 0) + 1
            if not entry.dynamic:
                unique.add((entry.platform, entry.text))
        print("entries by platform:", json.dumps(by_platform, sort_keys=True))
        print("entries by kind:", json.dumps(by_kind, sort_keys=True))
        print("unique static strings:", len(unique))

    if args.check:
        catalog = load_catalog()
        problems = [
            entry
            for entry in entries
            if entry.kind in {"ui", "error", "dynamic"} and not entry.wrapped
        ]
        missing = [entry for entry in problems if not entry.dynamic and entry.text not in catalog]
        dynamic = [entry for entry in problems if entry.dynamic]
        print(f"unwrapped UI/error strings: {len(problems)}")
        print(f"missing catalog entries: {len(missing)}")
        print(f"dynamic strings needing templates: {len(dynamic)}")
        for entry in (missing + dynamic)[:80]:
            print(f"{entry.file}:{entry.line}: [{entry.kind}] {entry.line_text}")
        return 1 if problems else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
