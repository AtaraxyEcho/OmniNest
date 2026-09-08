# -*- coding: utf-8 -*-
"""通用字号迁移：把目标模块的硬编码 fontSize 字面量替换为语义 token。

用法：python tool/migrate_font_sizes.py <module> [module ...] [--exclude-file=名字 ...]
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
    # 原型保真：reader/video 已验收原型中的微字规格（9/10）保留原值
    "KEEP": "KEEP",
}

MICRO_KEEP_VALUES = {"9", "10"}

def effective_token(value: str, keep_micro: bool) -> str:
    if keep_micro and value in MICRO_KEEP_VALUES:
        return "KEEP"
    return MAPPING.get(value)

PATTERN = re.compile(r"fontSize:\s*([0-9]+(?:\.[0-9]+)?)")
VIDEO_HELPER_PATTERN = re.compile(
    r"(?:serif|display|body|mono)\(\s*(?:size:\s*)?([0-9]+(?:\.[0-9]+)?)"
)
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


def migrate_file(path: Path, module: str, stats: dict, excludes: set) -> bool:
    original = path.read_text(encoding="utf-8-sig")
    is_part = bool(PART_OF_PATTERN.search(original))
    is_video = module == "video"
    has_sizes = "fontSize:" in original or (
        is_video and VIDEO_HELPER_PATTERN.search(original)
    )
    if not has_sizes:
        return False

    lines = original.split("\n")
    marked_indexes: list = []
    changed = False

    for i, line in enumerate(lines):
        previous = lines[i - 1] if i > 0 else ""
        if "font_size_whitelist" in line or "font_size_whitelist" in previous:
            continue
        whitelist_needed = []

        def replace(match: re.Match) -> str:
            value = match.group(1)
            token = effective_token(value, stats["keep_micro"])
            if token is None:
                stats["unmapped"].append(f"{module}: fontSize: {value}")
                return match.group(0)
            stats["counts"][value] = stats["counts"].get(value, 0) + 1
            if token in ("WHITELIST", "KEEP"):
                whitelist_needed.append(True)
                return match.group(0)
            return f"fontSize: AppTypography.{token}"

        def replace_helper(match: re.Match) -> str:
            value = match.group(1)
            token = effective_token(value, stats["keep_micro"])
            if token is None:
                stats["unmapped"].append(f"{module}: helper size: {value}")
                return match.group(0)
            stats["counts"][value] = stats["counts"].get(value, 0) + 1
            if token in ("WHITELIST", "KEEP"):
                whitelist_needed.append(True)
                return match.group(0)
            prefix = match.group(0)[: match.start(1) - match.start(0)]
            return prefix + f"AppTypography.{token}"

        new_line = PATTERN.sub(replace, line)
        if is_video:
            new_line = VIDEO_HELPER_PATTERN.sub(replace_helper, new_line)
        if new_line != line:
            lines[i] = new_line
            changed = True
        if whitelist_needed:
            marked_indexes.append(i)

    # 白名单标记（KEEP/WHITELIST）即使无内容变更也需落盘。
    needs_write = changed or bool(marked_indexes)
    if not needs_write:
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
        if host_match.group(1) in excludes:
            print(f"EXCLUDED part（宿主在途重写）: {path.name} → {host_match.group(1)}")
            return False
        host = path.parent / host_match.group(1)
        path.write_text(migrated, encoding="utf-8")
        if changed:
            host.write_text(insert_import(host.read_text(encoding="utf-8")), encoding="utf-8")
        stats["hosts"].append(
            str(host.relative_to(FRONTEND)).replace("\\", "/")
            + f" ← part: {path.name}"
        )
    else:
        if changed:
            migrated = insert_import(migrated)
        path.write_text(migrated, encoding="utf-8")

    stats["changed_files"].append(
        str(path.relative_to(FRONTEND)).replace("\\", "/")
    )
    return True


def migrate_module(module: str, excludes: set) -> None:
    target = FRONTEND / "lib" / ("core" if module == "core" else f"features/{module}")
    if not target.exists():
        print(f"SKIP（目录不存在）: {module}")
        return
    stats: dict = {
        "keep_micro": module in ("reader", "video"),
        "counts": {},
        "changed_files": [],
        "skipped_parts": [],
        "hosts": [],
        "unmapped": [],
    }
    for path in sorted(target.rglob("*.dart")):
        if path.name in excludes:
            print(f"EXCLUDED（在途重写，暂缓）: {path.name}")
            continue
        migrate_file(path, module, stats, excludes)

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
    modules = [a for a in sys.argv[1:] if not a.startswith("--exclude-file=")]
    excludes = {
        a.split("=", 1)[1]
        for a in sys.argv[1:]
        if a.startswith("--exclude-file=")
    }
    for module in modules:
        migrate_module(module, excludes)


if __name__ == "__main__":
    main()
