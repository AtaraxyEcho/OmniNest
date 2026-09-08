# -*- coding: utf-8 -*-
"""通用字号迁移：把目标模块的硬编码 fontSize 字面量替换为语义 token。

用法：python tool/migrate_font_sizes.py <module> [module ...]
模块名对应 lib/features/<module>；import 自动按字典序插入（part 文件的
import 加到宿主 library，part of 非文件名形式时跳过并报告）；
值映射到 'WHITELIST' 时保留原字面量并在上一行插入 ignore 标记。
"""
import re
import sys
from pathlib import Path

FRONTEND = Path(__file__).resolve().parents[1]
IMPORT_LINE = "import 'package:omninest/app/theme/app_typography.dart';"
WHITELIST_MARKER = "// ignore: font_size_whitelist"

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
    "26": "headlineMedium",
    "28": "headlineMedium",
    "30": "headlineLarge",
    "32": "headlineLarge",
    "34": "displaySmall",
    "36": "displaySmall",
    "45": "displayMedium",
    "48": "displayLarge",
    "56": "displayLarge",
    "58": "WHITELIST",
}

PATTERN = re.compile(r"fontSize:\s*([0-9]+(?:\.[0-9]+)?)")
PART_OF_PATTERN = re.compile(r"^part of '([^']+)';", flags=re.MULTILINE)


def insert_import(text: str) -> str:
    if IMPORT_LINE in text:
        return text
    lines = text.split("\n")
    insert_at = None
    token_import = IMPORT_LINE[len("import '"):-2]
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped.startswith("import 'package:omninest/"):
            continue
        existing = stripped[len("import '"):-2]
        if existing > token_import:
            insert_at = i
            break
    if insert_at is None:
        last_package_import = None
        for i, line in enumerate(lines):
            if line.strip().startswith("import 'package:"):
                last_package_import = i
        insert_at = (
            last_package_import + 1 if last_package_import is not None else 0
        )
    lines.insert(insert_at, IMPORT_LINE)
    return "\n".join(lines)


def migrate_file(path: Path, module: str, stats: dict) -> bool:
    original = path.read_text(encoding="utf-8-sig")
    if "fontSize:" not in original:
        return False
    is_part = bool(PART_OF_PATTERN.search(original))

    lines = original.split("\n")
    marked_indexes: list = []
    changed = False

    for i, line in enumerate(lines):
        if "font_size_whitelist" in line:
            continue
        whitelist_needed = []

        def replace(match: re.Match) -> str:
            value = match.group(1)
            token = MAPPING.get(value)
            if token is None:
                stats["unmapped"].append(f"{module}: fontSize: {value}")
                return match.group(0)
            stats["counts"][value] = stats["counts"].get(value, 0) + 1
            if token == "WHITELIST":
                whitelist_needed.append(True)
                return match.group(0)
            return f"fontSize: AppTypography.{token}"

        new_line = PATTERN.sub(replace, line)
        if new_line != line:
            lines[i] = new_line
            changed = True
        if whitelist_needed:
            marked_indexes.append(i)

    if not changed:
        return False

    for i in sorted(set(marked_indexes), reverse=True):
        lines.insert(i, WHITELIST_MARKER)
    migrated = "\n".join(lines)

    if is_part:
        host_match = PART_OF_PATTERN.search(original)
        if host_match is None:
            stats["skipped_parts"].append(
                f"{path}（part of 非文件名形式，需手工处理）"
            )
            return False
        host = path.parent / host_match.group(1)
        path.write_text(migrated, encoding="utf-8")
        host.write_text(insert_import(host.read_text(encoding="utf-8")), encoding="utf-8")
        stats["hosts"].append(
            str(host.relative_to(FRONTEND)).replace("\\", "/")
            + f" ← part: {path.name}"
        )
    else:
        migrated = insert_import(migrated)
        path.write_text(migrated, encoding="utf-8")

    stats["changed_files"].append(
        str(path.relative_to(FRONTEND)).replace("\\", "/")
    )
    return True


def migrate_module(module: str) -> None:
    target = FRONTEND / "lib" / "features" / module
    if not target.exists():
        print(f"SKIP（目录不存在）: {module}")
        return
    stats: dict = {
        "counts": {},
        "changed_files": [],
        "skipped_parts": [],
        "hosts": [],
        "unmapped": [],
    }
    for path in sorted(target.rglob("*.dart")):
        migrate_file(path, module, stats)

    print(f"== {module} ==")
    print(f"changed files: {len(stats['changed_files'])}")
    for name in stats["changed_files"]:
        print(f"  {name}")
    print("replacements by value:")
    for value in sorted(stats["counts"], key=lambda v: float(v)):
        token = MAPPING[value]
        suffix = "（白名单保留）" if token == "WHITELIST" else f"→ {token}"
        print(f"  {value} {suffix} : {stats['counts'][value]}")
    if stats["hosts"]:
        print("hosts updated for part files:")
        for item in stats["hosts"]:
            print(f"  {item}")
    if stats["skipped_parts"]:
        print("SKIPPED part files:")
        for item in stats["skipped_parts"]:
            print(f"  {item}")
    if stats["unmapped"]:
        print("UNMAPPED (left as-is):")
        for item in stats["unmapped"]:
            print(f"  {item}")


def main() -> None:
    if len(sys.argv) < 2:
        print("用法: python tool/migrate_font_sizes.py <module> [module ...]")
        sys.exit(1)
    for module in sys.argv[1:]:
        migrate_module(module)


if __name__ == "__main__":
    main()
