import shutil
import unittest
import uuid
from pathlib import Path

import convert_rime_frost_pyim as converter


class RimeFrostPyimTests(unittest.TestCase):
    def test_converts_rime_pinyin_to_pyim_code(self):
        self.assertEqual("ni-hao", converter.convert_rime_pinyin_to_pyim_code("ni hao"))
        self.assertEqual("nv-er", converter.convert_rime_pinyin_to_pyim_code("nü er"))

    def test_parses_tab_separated_rime_entries(self):
        entry = converter.parse_rime_line("你好\tni hao\t9000", 3)
        self.assertIsNotNone(entry)
        self.assertEqual("你好", entry.word)
        self.assertEqual("ni-hao", entry.code)
        self.assertEqual(9000, entry.weight)
        self.assertEqual(3, entry.order)
        self.assertIsNone(converter.parse_rime_line("bad line without tabs", 4))

    def test_writes_imported_tables_in_pyim_format(self):
        cache_dir = Path(__file__).resolve().parents[1] / ".cache"
        cache_dir.mkdir(exist_ok=True)
        root = cache_dir / f"rime-frost-pyim-test-{uuid.uuid4().hex}"
        root.mkdir()
        try:
            (root / "cn_dicts").mkdir()
            (root / "rime_frost.dict.yaml").write_text(
                "\n".join(
                    [
                        "# Rime dictionary",
                        "---",
                        "name: rime_frost",
                        "import_tables:",
                        "  - cn_dicts/base",
                        "...",
                    ]
                ),
                encoding="utf-8",
            )
            (root / "cn_dicts" / "base.dict.yaml").write_text(
                "\n".join(
                    [
                        "# Rime dictionary",
                        "---",
                        "name: base",
                        "...",
                        "你好\tni hao\t1",
                        "你号\tni hao\t9",
                        "女儿\tnü er\t5",
                    ]
                ),
                encoding="utf-8",
            )

            output = root / "rime-frost.pyim"
            stats = converter.convert(root, "rime_frost.dict.yaml", output)

            self.assertEqual(2, stats.file_count)
            self.assertEqual(3, stats.entry_count)
            self.assertEqual(2, stats.code_count)
            self.assertEqual(
                [
                    "# ;;; -*- coding: utf-8-unix -*-",
                    "# Generated from gaboolic/rime-frost by scripts/convert-rime-frost-pyim.py.",
                    "ni-hao 你号 你好",
                    "nv-er 女儿",
                ],
                output.read_text(encoding="utf-8").splitlines(),
            )
        finally:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
