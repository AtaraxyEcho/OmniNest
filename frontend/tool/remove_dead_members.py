# -*- coding: utf-8 -*-
"""按 (文件, 成员名) 删除死声明。统一扫描：声明行判定 + 括号深度终止。"""
import io
import os
import re

PKG = r"D:\Development\Project Collection\OmniNest\frontend"

TARGETS = [
    ("lib/features/reader/presentation/widgets/reader_control_layout.dart", "anchorViewportY"),
    ("lib/features/reader/presentation/widgets/reader_view_settings.dart", "annotationColor"),
    ("lib/features/reader/presentation/widgets/reader_content_loader.dart", "blockIndexToCharOffset"),
    ("lib/features/reader/presentation/widgets/reader_content_loader.dart", "charOffsetToBlockIndex"),
    ("lib/features/reader/presentation/widgets/reader_content_loader.dart", "invalidateAllSlices"),
    ("lib/features/reader/presentation/widgets/reader_content_loader.dart", "invalidateCache"),
    ("lib/features/reader/presentation/widgets/reader_content_loader.dart", "prefetchAdjacentPages"),
    ("lib/features/reader/presentation/widgets/reader_content_loader.dart", "probePage"),
    ("lib/features/reader/presentation/widgets/reader_content_loader.dart", "probePageCount"),
    ("lib/features/reader/presentation/widgets/reader_content_loader.dart", "updateSlices"),
    ("lib/features/reader/presentation/widgets/reader_progress_helper.dart", "progressFromCharOffset"),
    ("lib/features/reader/presentation/reader_l10n_helpers.dart", "readerSortLabel"),
    ("lib/features/reader/presentation/widgets/reader_view_page_interaction_mixin.dart", "repaginateAll"),
    ("lib/features/reader/presentation/widgets/reader_pagination_engine.dart", "paginate"),
    ("lib/features/reader/presentation/widgets/reader_position_tracker.dart", "toPayload"),
    ("lib/features/reader/application/reader_progress_snapshot.dart", "toPayload"),
    ("lib/features/reader/domain/comic_models.dart", "isChapter"),
    ("lib/features/reader/domain/comic_models.dart", "pagesByCatalog"),
    ("lib/features/reader/domain/comic_layout_index.dart", "topOffset"),
    ("lib/features/reader/domain/parsed_book.dart", "withContent"),
    ("lib/features/reader/data/reader_api.dart", "generateComicManifest"),
    ("lib/features/reader/data/reader_image_cache.dart", "saveImages"),
    ("lib/features/reader/data/reader_local_storage.dart", "cleanAllCache"),
    ("lib/features/reader/data/reader_local_storage.dart", "loadBookDetail"),
    ("lib/features/reader/data/reader_local_storage.dart", "saveBookDetail"),
    ("lib/features/reader/data/local_book_cache.dart", "getCacheSize"),
    ("lib/features/reader/data/local_book_cache.dart", "getTotalCacheSize"),
    ("lib/features/reader/application/reader_data_manager.dart", "flushSyncQueue"),
    ("lib/features/reader/application/reader_controller.dart", "waitForImportCandidate"),
    ("lib/features/reader/presentation/widgets/reader_pagination_engine.dart", "_paginateContinuous"),
    ("lib/features/reader/presentation/widgets/reader_pagination_engine.dart", "_paginateByBlock"),
    ("lib/features/reader/presentation/widgets/reader_pagination_engine.dart", "_buildLineRefs"),
    ("lib/features/reader/presentation/widgets/reader_pagination_engine.dart", "_buildTextSpan"),
    ("lib/features/reader/presentation/widgets/reader_pagination_engine.dart", "_paginateLines"),
    ("lib/features/reader/presentation/widgets/reader_pagination_engine.dart", "_lineHeightInTextPainter"),
    ("lib/features/reader/presentation/widgets/reader_pagination_engine.dart", "_closePage"),
    ("lib/features/reader/data/reader_local_storage.dart", "allProgress"),
    ("lib/features/reader/data/reader_local_storage.dart", "cleanAllChapterCache"),
    ("lib/features/reader/presentation/widgets/reader_content_loader.dart", "invalidateSlices"),
    ("lib/features/reader/presentation/widgets/reader_content_loader.dart", "prefetchAdjacent"),
]

NOT_DECL_PREFIX = ("return", ".", "=>", "=", "}", ")", "]", "//", "*", "++", "--")


def find_decl(lines, name):
    name_re = re.compile(r"\b" + re.escape(name) + r"\b")
    for idx, line in enumerate(lines):
        if not name_re.search(line):
            continue
        m = name_re.search(line)
        prefix = line[: m.start()].strip()
        suffix = line[m.end():].strip()
        if not prefix or any(p in prefix for p in NOT_DECL_PREFIX):
            continue
        if prefix.split()[-1] not in ("get", "set") and not re.search(
            r"[\w<>\].?]$", prefix
        ):
            continue
        if not (suffix.startswith(("(", "=", ";", "{")) or suffix == ""):
            continue
        if suffix == "" and "=>" not in line and "(" not in line and ";" not in line:
            continue
        return idx
    return None


def statement_end(lines, start_idx):
    """返回 (end_line_exclusive)。括号深度统一扫描；代码大括号（前字符
    非 = , ( [ : 时）视为方法体，结束于配对 }。"""
    pd = 0
    bd = 0
    body = False
    started = False
    for i in range(start_idx, len(lines)):
        line = lines[i]
        j = 0
        n = len(line)
        in_str = None
        while j < n:
            c = line[j]
            if in_str:
                if c == "\\":
                    j += 2
                    continue
                if c == in_str:
                    in_str = None
                j += 1
                continue
            if c in "\"'":
                in_str = c
                j += 1
                continue
            if c == "(":
                pd += 1
            elif c == ")":
                pd -= 1
            elif c == "{":
                prev = line[:j].rstrip()
                prev_ch = prev[-1] if prev else ""
                if pd == 0 and bd == 0 and prev_ch not in ("=", ",", "(", "[", ":"):
                    body = True
                    started = True
                bd += 1
            elif c == "}":
                bd -= 1
                if body and bd == 0 and pd == 0:
                    return i + 1
            elif c == ";" and pd == 0 and bd == 0:
                return i + 1
            j += 1
        if not started and pd == 0 and bd == 0 and i > start_idx:
            s = lines[i].strip()
            if s and not s.startswith(("@", "//", "///", "*", "}")) and not s.endswith(
                (",", "{", ";", ")", "=>", "]", "}", "(")
            ):
                return i  # 空行/下一声明前
    return len(lines)


def remove_member(text, name):
    lines = text.split("\n")
    idx = find_decl(lines, name)
    if idx is None:
        return None, "decl-not-found"
    # 向上吃 @override 与文档注释
    s = idx
    while s > 0:
        prev = lines[s - 1].strip()
        if prev.startswith(("@override", "///", "//")):
            s -= 1
        else:
            break
    e = statement_end(lines, idx)
    # 吃掉后面的连续空行
    while e < len(lines) and lines[e].strip() == "":
        e += 1
    new_lines = lines[:s] + lines[e:]
    return "\n".join(new_lines), "%d-%d" % (s + 1, e)


for rel, name in TARGETS:
    path = os.path.join(PKG, rel.replace("/", os.sep))
    text = io.open(path, encoding="utf-8").read()
    new_text, info = remove_member(text, name)
    if new_text is None:
        print("FAIL %-58s %-28s %s" % (rel, name, info))
        continue
    io.open(path, "w", encoding="utf-8", newline="").write(new_text)
    print("OK   %-58s %-28s lines %s" % (rel, name, info))
