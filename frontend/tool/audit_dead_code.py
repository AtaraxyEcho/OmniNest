# -*- coding: utf-8 -*-
"""Reader 模块死代码审查：声明级零引用扫描 + 文件级孤儿 + 未用 l10n key。"""
import io
import os
import re

PKG = r"D:\Development\Project Collection\OmniNest\frontend"
READER = os.path.join(PKG, "lib", "features", "reader")
ARB = os.path.join(PKG, "lib", "app", "l10n", "app_en.arb")

dart_files = []
for base in ("lib", "test"):
    for root, _dirs, files in os.walk(os.path.join(PKG, base)):
        for f in files:
            if f.endswith(".dart"):
                dart_files.append(os.path.join(root, f))
content = {p: io.open(p, encoding="utf-8").read() for p in dart_files}

reader_files = [
    p for p in dart_files
    if p.replace("\\", "/").startswith(READER.replace("\\", "/"))
]

# ── 1. 声明抽取（方法/构造/getter/setter/字段/类/mixin/enum）──
decl_patterns = [
    # 方法与构造：缩进 2-8 的 name( 声明，前面有返回类型 token
    re.compile(r"^[ \t]{2,8}(?:static\s+|final\s+|const\s+|late\s+|abstract\s+)*"
               r"[A-Za-z_][\w<>?,\s.?]*?[ \t]+\b(\w+)[ \t]*\(", re.M),
    # getter/setter
    re.compile(r"^[ \t]{2,8}[\w<>?,\s.?]+?\bget[ \t]+(\w+)", re.M),
    re.compile(r"^[ \t]{2,8}[\w<>?,\s.?]+?\bset[ \t]+(\w+)", re.M),
    # 字段：final/const/late/类型 + name = 或 ;
    re.compile(r"^[ \t]{2,8}(?:static\s+)?(?:final|const|late)\s+"
               r"[\w<>?,\s.?]+?[ \t]+(\w+)\s*(?:=|;)", re.M),
    # 类/mixin/enum/typedef/顶层函数
    re.compile(r"^\s*(?:abstract\s+)?(?:sealed\s+)?(?:class|mixin|enum|typedef)"
               r"\s+(\w+)", re.M),
    re.compile(r"^(?:Future<[^>]*>|[\w<>?,\s]+?)\s+(\w+)\s*\([^;{]*\)\s*\{?\s*$",
               re.M),
]

all_names = {}
for path in reader_files:
    text = content[path]
    rel = os.path.relpath(path, PKG).replace("\\", "/")
    seen = set()
    for pat in decl_patterns:
        for m in pat.finditer(text):
            name = m.group(1)
            if name in {"if", "for", "while", "switch", "return", "catch",
                        "new", "super", "this", "else", "do"}:
                continue
            if name in seen:
                continue
            seen.add(name)
            all_names.setdefault(name, []).append(rel)

# ── 2. 引用计数（lib+test 全域词边界匹配）──
usage_text = {p: text for p, text in content.items()}
dead_candidates = []
for name, decl_files in sorted(all_names.items()):
    if len(name) < 4:
        continue
    pat = re.compile(r"\b" + re.escape(name) + r"\b")
    refs = 0
    for path, text in content.items():
        for m in pat.finditer(text):
            refs += 1
    # 声明自身占用：每处声明占 1 次（粗略），剩余 0 视为候选
    if refs <= len(decl_files):
        dead_candidates.append((name, decl_files))

print("=== 声明级零引用候选（%d 个）===" % len(dead_candidates))
for name, files in dead_candidates:
    print("  %-42s %s" % (name, ", ".join(sorted(set(files)))))

# ── 3. 文件级孤儿：reader 文件未被任何 import/part 引用 ──
import_text = "\n".join(content[p] for p in dart_files)
print("\n=== 文件级孤儿 ===")
for path in reader_files:
    base = os.path.basename(path)[:-5]
    rel = os.path.relpath(path, PKG).replace("\\", "/")
    if rel.endswith("reader_debug_log.dart") or "/reader.dart" in rel:
        continue
    pat = re.compile(r"[" + re.escape("/") + r"\\\\/]" + re.escape(base)
                     + r"\.dart")
    if not pat.search(import_text):
        print("  %s" % rel)

# ── 4. 未用 l10n key（reader 前缀）──
if os.path.exists(ARB):
    arb = io.open(ARB, encoding="utf-8").read()
    keys = re.findall(r'"(reader[A-Z]\w+)"\s*:', arb)
    lib_text = "\n".join(content[p] for p in dart_files
                         if p.replace("\\", "/").startswith(
                             os.path.join(PKG, "lib").replace("\\", "/")))
    unused = [k for k in keys
              if not re.search(r"\." + k + r"\b", lib_text)]
    print("\n=== 未用 l10n key（%d 个）===" % len(unused))
    for k in unused:
        print("  %s" % k)
