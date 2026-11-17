"""从设计稿导出「移动深浅适配的样例事实表」。

用法：
    python tool/light_sample_values.py <样例 src 目录> > tool/light_mode_sample_values.txt

样例目录不在仓库内（Figma Make 导出的 React 工程），本脚本不是构建或测试依赖，
只在人工刷新事实表时运行；仓库里被消费的是它的输出 `tool/light_mode_sample_values.txt`
与角色映射 `tool/light_sample_roles.json`。

求值口径（三条，都是踩过坑之后定下来的）：
1. 后写覆盖前写，但 `:where(...)` 的内容特异度为 0——样例第 5 层那批 11px 微型字号
   因此被第 1 层的显式选择器压回，两极性字号实际一致。
2. 简写与长写归一：`background: #f1f4ed` 会清掉先前的 `background-color: var(--surface)`，
   反之亦然；不归一会把半透表面读成实底（或反过来）。
3. `@media` 内的规则是条件态（hover、prefers-reduced-motion），不入默认值表。
"""

import json
import re
import sys

SAMPLE_ARG = 1
ROLES_ARG = 2


def strip_comments(text):
    return re.sub(r"/\*.*?\*/", "", text, flags=re.S)


def rules(text, in_media=False):
    """产出 (selector, body, 起始行, 是否位于 @media 内)，按文件顺序。"""
    text = strip_comments(text)
    out = []
    line = 1
    buf = ""
    depth = 0
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\n":
            line += 1
        if ch == ";" and depth == 0:
            # 语句（@import 等）不能粘进下一条规则的选择器里。
            buf = ""
            i += 1
            continue
        if ch == "{":
            if depth == 0:
                sel = buf.strip()
                body_start = line
                body = ""
                depth = 1
                i += 1
                while i < len(text) and depth > 0:
                    if text[i] == "\n":
                        line += 1
                    if text[i] == "{":
                        depth += 1
                    elif text[i] == "}":
                        depth -= 1
                        if depth == 0:
                            break
                    body += text[i]
                    i += 1
                if sel.startswith("@media") or sel.startswith("@supports"):
                    out.extend(rules(body, in_media=True))
                elif not sel.startswith("@"):
                    out.append((sel, body, body_start, in_media))
                buf = ""
                i += 1
                continue
            depth += 1
        buf += ch
        i += 1
    return out


SHORTHAND_LONGHANDS = {
    "background": ("background-color", "background-image"),
    "border": ("border-color", "border-width", "border-style"),
    "border-top": ("border-top-color", "border-top-width", "border-top-style"),
    "border-bottom": ("border-bottom-color", "border-bottom-width"),
    "inset": ("top", "right", "bottom", "left"),
    "padding": ("padding-top", "padding-right", "padding-bottom", "padding-left"),
    "margin": ("margin-top", "margin-right", "margin-bottom", "margin-left"),
}

COLOR_IN_VALUE = re.compile(
    r"#[0-9a-fA-F]{3,8}\b|(?:rgba?|hsla?)\([^)]*\)|var\(--[a-z-]+\)"
    r"|\b(?:transparent|white|black)\b"
)


def normalize_props(decls):
    out = {}
    for prop, value in decls.items():
        if prop in SHORTHAND_LONGHANDS:
            for shadowed in SHORTHAND_LONGHANDS[prop]:
                out.pop(shadowed, None)
            key = None
            if prop == "background":
                key = (
                    "background-image"
                    if "gradient(" in value[0] or "url(" in value[0]
                    else "background-color"
                )
            elif prop.startswith("border"):
                found = COLOR_IN_VALUE.search(value[0])
                if found:
                    key = prop + "-color"
                    value = (found.group(0), value[1])
            out[prop] = value
            if key:
                out[key] = value
            continue
        for short, longs in SHORTHAND_LONGHANDS.items():
            if prop in longs:
                out.pop(short, None)
        out[prop] = value
    return out


def parse_decls(body, start):
    decls = {}
    for line in body.split(";"):
        if ":" not in line:
            continue
        prop, _, val = line.partition(":")
        prop = prop.strip()
        val = " ".join(val.split())
        if prop and val:
            decls[prop] = (val, start)
    return normalize_props(decls)


def split_selectors(sel):
    """按顶层逗号切分选择器组；括号内的逗号（:where(a, b)）不算分隔符。"""
    parts = []
    depth = 0
    buf = ""
    for ch in sel:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(buf)
            buf = ""
            continue
        buf += ch
    parts.append(buf)
    return [p for p in (x.strip() for x in parts) if p]


def normalize(sel):
    sel = " ".join(sel.split())
    sel = re.sub(r"^html\[data-polarity=\"(dark|light)\"\]\s*", "", sel)
    mode = None
    m = re.match(r"^\[data-mode=\"(\w+)\"\]\s*(.*)$", sel)
    if m:
        mode, sel = m.group(1), m.group(2)
    keys = []
    wm = re.match(r"^:where\(([^)]*)\)(.*)$", sel, flags=re.S)
    if wm:
        for part in split_selectors(wm.group(1)):
            keys.append((mode, (part.strip() + wm.group(2)).strip()))
    else:
        keys.append((mode, sel))
    return keys


def specificity(sel):
    s = re.sub(r":(where|is)\([^)]*\)", "", sel)
    classes = len(re.findall(r"\.[A-Za-z0-9_-]+|\[[^\]]+\]|:[a-zA-Z-]+", s))
    types = len(re.findall(r"(?<![\w.#-])[a-z][a-z0-9]*(?![\w-])", s))
    return classes * 10 + types


def collect(path):
    text = open(path, encoding="utf-8").read()
    pending = {}
    for sel, body, start, in_media in rules(text):
        decls = parse_decls(body, start)
        if not decls:
            continue
        for one in split_selectors(sel):
            for mode, key in normalize(one):
                pending.setdefault((key, mode), []).append(
                    (specificity(one), start, in_media, decls)
                )
    table = {}
    for k, entries in pending.items():
        merged = {}
        for spec, order, in_media, decls in sorted(entries, key=lambda e: (e[0], e[1])):
            if in_media:
                continue
            merged.update(decls)
        table[k] = merged
    return table


def token_block(table, root_key):
    return table.get((root_key, None), {})


def resolve(table, root_key, value, depth=0):
    m = re.fullmatch(r"var\((--[a-z-]+)\)", value.strip())
    if not m or depth > 4:
        return value.strip()
    entry = token_block(table, root_key).get(m.group(1))
    if entry is None:
        return "UNRESOLVED(%s)" % m.group(1)
    return resolve(table, root_key, entry[0], depth + 1)


def grad_stop(value, index):
    stops = re.findall(r"rgba?\([^)]*\)|#[0-9a-fA-F]{3,8}", value)
    return stops[index] if index < len(stops) else "-"


def fn_arg(value, name):
    m = re.search(r"%s\(([^)]*)\)" % name, value or "")
    return m.group(1) if m else "-"


def lookup(table, root_key, role):
    sel, mode, prop, var_name = role[1], role[2], role[3], role[4]
    decls = table.get((sel, mode), {})
    if prop == "@@var":
        entry = token_block(table, root_key).get(var_name)
        return resolve(table, root_key, entry[0], 1) if entry else "-"
    if prop.startswith("@@grad"):
        entry = decls.get("background") or decls.get("background-image")
        return grad_stop(entry[0], int(prop[-1])) if entry else "-"
    if prop.startswith("@@fn:"):
        entry = decls.get("filter")
        return fn_arg(entry[0], prop.split(":")[1]) if entry else "-"
    entry = decls.get(prop)
    if entry is None:
        return "-"
    return resolve(table, root_key, entry[0])


HEADER = [
    "# 移动深浅适配的样例事实表：由设计稿 index.css（暗）与 light-theme.css（浅）的级联最终值导出。",
    "# 刷新方式：python tool/light_sample_values.py <样例 src 目录> ；角色映射见 tool/light_sample_roles.json。",
    "# 样例目录不在仓库内，本文件就是它在仓库里的那一份事实；改浅态或暗态配色必须同步改这里。",
    "# 求值口径：后写覆盖前写，但 :where() 内容特异度为 0（样例第 5 层的 11px 微型字号因此不生效，",
    "# 微型字号两极性一致）；简写与长写互相归一；@media 内的条件态不入表。",
    "# 格式：角色<TAB>暗值<TAB>浅值<TAB>#来源选择器；'-' 表示样例该极性未声明这一项。",
]


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("用法: python tool/light_sample_values.py <样例 src 目录>\n")
        return 2
    src = sys.argv[1].rstrip("/\\")
    roles_path = (
        sys.argv[2]
        if len(sys.argv) > 2
        else "tool/light_sample_roles.json"
    )
    dark = collect(src + "/index.css")
    light = collect(src + "/light-theme.css")
    roles = json.load(open(roles_path, encoding="utf-8"))
    lines = list(HEADER)
    for role in roles:
        src_text = role[1] + (
            "" if role[2] is None else "[data-mode=%s]" % role[2]
        )
        lines.append(
            "%s\t%s\t%s\t# %s"
            % (role[0], lookup(dark, ":root", role), lookup(light, "", role), src_text)
        )
    sys.stdout.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
