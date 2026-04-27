from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


PINYIN_RE = re.compile(r"^[a-zvü:']+(\s+[a-zvü:']+)*$", re.IGNORECASE)


@dataclass(frozen=True)
class Entry:
    word: str
    code: str
    weight: int
    order: int


@dataclass(frozen=True)
class ConvertStats:
    file_count: int
    entry_count: int
    code_count: int


def convert_rime_pinyin_to_pyim_code(pinyin: str) -> str:
    normalized = pinyin.strip().lower()
    normalized = normalized.replace("u:", "v").replace("ü", "v").replace("'", " ")
    return "-".join(part for part in normalized.split() if part)


def is_rime_pinyin_code(pinyin: str) -> bool:
    normalized = pinyin.strip()
    return bool(PINYIN_RE.fullmatch(normalized))


def parse_rime_line(line: str, order: int) -> Entry | None:
    line = line.lstrip("\ufeff").rstrip("\n\r")
    stripped = line.strip()

    if not stripped or stripped.startswith("#"):
        return None

    line = re.sub(r"\s+#.*$", "", line)
    parts = re.split(r"\t+", line)
    if len(parts) < 2:
        return None

    word = parts[0].strip()
    pinyin = parts[1].strip()
    if not word or any(ch.isspace() for ch in word) or not is_rime_pinyin_code(pinyin):
        return None

    weight = 0
    if len(parts) >= 3:
        weight_text = parts[2].strip().split()
        if weight_text:
            try:
                weight = int(weight_text[0])
            except ValueError:
                weight = 0

    return Entry(
        word=word,
        code=convert_rime_pinyin_to_pyim_code(pinyin),
        weight=weight,
        order=order,
    )


def import_tables(dictionary_path: Path) -> list[str]:
    imports: list[str] = []
    in_import_tables = False

    with dictionary_path.open("r", encoding="utf-8-sig", newline="") as handle:
        for raw_line in handle:
            stripped = raw_line.strip()
            if stripped == "...":
                break

            if re.match(r"^import_tables\s*:", stripped):
                in_import_tables = True
                continue

            if not in_import_tables or not stripped or stripped.startswith("#"):
                continue

            if re.match(r"^[A-Za-z0-9_-]+\s*:", stripped):
                in_import_tables = False
                continue

            match = re.match(r"^-\s*([^#\s]+)", stripped)
            if match:
                imports.append(match.group(1).strip("'\""))

    return imports


def resolve_dictionary(root: Path, table_name: str) -> Path:
    relative = Path(*table_name.split("/"))
    candidates = [
        root / relative,
        root / f"{relative}.dict.yaml",
        root / f"{relative}.yaml",
    ]

    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()

    raise FileNotFoundError(f"Cannot resolve Rime dictionary table {table_name!r} under {root}.")


def dictionary_files(root: Path, entry_dictionary: str) -> list[Path]:
    files: list[Path] = []
    visited: set[Path] = set()

    def add_file(path: Path) -> None:
        resolved = path.resolve()
        if resolved in visited:
            return

        visited.add(resolved)
        for table in import_tables(resolved):
            add_file(resolve_dictionary(root, table))
        files.append(resolved)

    add_file(resolve_dictionary(root, entry_dictionary))
    return files


def read_entries(files: list[Path]) -> list[Entry]:
    entries: list[Entry] = []
    order = 0

    for path in files:
        in_body = False
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            for line in handle:
                if line.strip() == "...":
                    in_body = True
                    continue

                if not in_body:
                    continue

                entry = parse_rime_line(line, order)
                if entry is None:
                    continue

                entries.append(entry)
                order += 1

    return entries


def write_pyim_dictionary(entries: list[Entry], output_path: Path) -> int:
    by_code: dict[str, dict[str, tuple[int, int]]] = {}

    for entry in entries:
        words = by_code.setdefault(entry.code, {})
        previous = words.get(entry.word)
        if previous is None or entry.weight > previous[0]:
            words[entry.word] = (entry.weight, entry.order)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("# ;;; -*- coding: utf-8-unix -*-\n")
        handle.write("# Generated from gaboolic/rime-frost by scripts/convert-rime-frost-pyim.py.\n")

        for code in sorted(by_code):
            ordered_words = sorted(by_code[code].items(), key=lambda item: (-item[1][0], item[1][1]))
            words = " ".join(word for word, _metadata in ordered_words)
            handle.write(f"{code} {words}\n")

    return len(by_code)


def convert(root: Path, entry_dictionary: str, output_path: Path) -> ConvertStats:
    root = root.resolve()
    files = dictionary_files(root, entry_dictionary)
    entries = read_entries(files)
    code_count = write_pyim_dictionary(entries, output_path.resolve())
    return ConvertStats(file_count=len(files), entry_count=len(entries), code_count=code_count)


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert rime-frost dictionaries to pyim format.")
    parser.add_argument("--root", required=True, type=Path, help="Path to a rime-frost checkout.")
    parser.add_argument("--entry", default="rime_frost.dict.yaml", help="Entry Rime dictionary file.")
    parser.add_argument("--output", required=True, type=Path, help="Output .pyim dictionary path.")
    args = parser.parse_args()

    stats = convert(args.root, args.entry, args.output)
    print(f"Read {stats.file_count} Rime dictionary files.")
    print(f"Converted {stats.entry_count} Rime entries.")
    print(f"Wrote {stats.code_count} pyim code lines.")
    print(f"Wrote pyim dictionary: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
