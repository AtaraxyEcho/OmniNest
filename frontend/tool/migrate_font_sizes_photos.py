# -*- coding: utf-8 -*-
"""P1 试点：photos 模块硬编码字号 → AppTypography 语义 token 一次性迁移。

按定稿映射表就近收敛；跳过行级白名单；自动按字典序插入 import。
"""
import re
from pathlib import Path

FRONTEND = Path(__file__).resolve().parents[1]
TARGET = FRONTEND / "lib" / "features" / "photos"
IMPORT_LINE = "import 'package:omninest/app/theme/app_typography.dart';"

MAPPING = {
    "9": "labelSmall",
    "10": "labelSmall",
    "10.5": "labelSmall",
    "11": "labelSmall",
    "12": "bodySmall",
    "13": "bodyMedium",
    "14": "bodyLarge",
    "15": "titleMedium",
    "16": "titleMedium",
    "18": "titleLarge",
    "19": "titleLarge",
    "20": "titleLarge",
    "22": "headlineSmall",
    "23": "headlineSmall",
    "24": "headlineSmall",
}

PATTERN = re.compile(r"fontSize:\s*([0-9]+(?:\.[0-9]+)?)")


def insert_import(text: str) -> str:
    if IMPORT_LINE in text:
        return text
    lines = text.split("\n")
    insert_at = None
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped.startswith("import 'package:omninest/"):
            continue
        existing = stripped[len("import '"):-2]
        if existing > IMPORT_LINE[len("import '"):-2]:
            insert_at = i
            break
    if insert_at is None:
        last_package_import = None
        for i, line in enumerate(lines):
            if line.strip().startswith("import 'package:"):
                last_package_import = i
        if last_package_import is not None:
            insert_at = last_package_import + 1
        else:
            first_import = min(
                (i for i, line in enumerate(lines) if line.strip().startswith("import ")),
                default=0,
            )
            insert_at = first_import
    lines.insert(insert_at, IMPORT_LINE)
    return "\n".join(lines)


def main() -> None:
    counts: dict = {}
    changed_files: list = []
    unmapped: list = []
    for path in sorted(TARGET.rglob("*.dart")):
        original = path.read_text(encoding="utf-8")
        if "fontSize:" not in original:
            continue

        def replace(match: re.Match) -> str:
            value = match.group(1)
            token = MAPPING.get(value)
            if token is None:
                unmapped.append(f"{path.name}: fontSize: {value}")
                return match.group(0)
            counts[value] = counts.get(value, 0) + 1
            return f"fontSize: AppTypography.{token}"

        migrated = PATTERN.sub(replace, original)
        if migrated == original:
            continue
        migrated = insert_import(migrated)
        path.write_text(migrated, encoding="utf-8")
        changed_files.append(str(path.relative_to(FRONTEND)).replace("\\", "/"))

    print(f"changed files: {len(changed_files)}")
    for name in changed_files:
        print(f"  {name}")
    print("replacements by value:")
    for value in sorted(counts, key=lambda v: float(v)):
        print(f"  {value} -> {MAPPING[value]} : {counts[value]}")
    total = sum(counts.values())
    print(f"total replacements: {total}")
    if unmapped:
        print("UNMAPPED (left as-is):")
        for item in unmapped:
            print(f"  {item}")


if __name__ == "__main__":
    main()
