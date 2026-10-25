"""按 GB2312 与界面文案子集化 CJK 字体，缩小 Web 首屏与安装包体积。

用法（在 frontend 目录执行）：
    python tool/subset_cjk_fonts.py

依赖：fontTools（pyftsubset 同包）。
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

FRONTEND = Path(__file__).resolve().parent.parent
FONT_DIR = FRONTEND / "assets" / "fonts"
ARB = FRONTEND / "lib" / "app" / "l10n" / "app_zh.arb"

FONTS = [
    "NotoSansSC-VF.ttf",
    "NotoSerifSC-Regular.otf",
]

EXTRA_CHARS = set(
    "　、。〃〈〉《》「」『』【】〔〕〖〗〝〞〜〟〰〽㈠㈡㈢㈣㈤㈥㈦㈧㈨㈩"
    "！＂＃＄％＆＇（）＊＋，－．／０１２３４５６７８９：；＜＝＞？＠"
    "［＼］＾＿｀｛｜｝～￥…—–‘’“”·×÷±°′″‰※→←↑↓↔⇒⇔✓✔✕✖"
    "①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳"
)


def gb2312_chars() -> set[str]:
    """GB2312 常用汉字与符号（约 6.7k），覆盖界面与绝大多数正文用字。

    生僻字（超出 GB2312 的人名、古籍用字）不在子集内，Web 端可能显示豆腐块；
    这是体积与覆盖面的显式取舍，需要全书级生僻字支持时应关闭子集化。
    """
    chars: set[str] = set()
    for first in range(0xA1, 0xF8):
        for second in range(0xA1, 0xFF):
            try:
                chars.add(bytes([first, second]).decode("gb2312"))
            except UnicodeDecodeError:
                continue
    return chars


def arb_chars() -> set[str]:
    chars: set[str] = set()
    if not ARB.is_file():
        return chars
    payload = json.loads(ARB.read_text(encoding="utf-8"))
    for value in payload.values():
        if isinstance(value, str):
            chars.update(ch for ch in value if ord(ch) > 0x7F)
    return chars


def build_charset() -> str:
    chars = {chr(code) for code in range(0x20, 0x7F)}
    chars |= gb2312_chars()
    chars |= arb_chars()
    chars |= EXTRA_CHARS
    return "".join(sorted(chars))


def subset(font_name: str, charset_file: Path) -> Path:
    source = FONT_DIR / font_name
    if not source.is_file():
        raise SystemExit(f"字体不存在: {source}")
    # 输出必须与源文件同盘，Windows 的 os.replace 不能跨卷移动。
    output = FONT_DIR / f".subset-{font_name}"
    command = [
        sys.executable,
        "-m",
        "fontTools.subset",
        str(source),
        f"--text-file={charset_file}",
        f"--output-file={output}",
        "--layout-features=*",
        "--glyph-names",
        "--symbol-cmap",
        "--legacy-cmap",
        "--notdef-glyph",
        "--notdef-outline",
        "--recommended-glyphs",
    ]
    subprocess.run(command, check=True)
    return output


def main() -> None:
    charset = build_charset()
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", suffix=".txt", delete=False
    ) as handle:
        handle.write(charset)
        charset_file = Path(handle.name)
    try:
        for font in FONTS:
            source = FONT_DIR / font
            before = source.stat().st_size
            output = subset(font, charset_file)
            after = output.stat().st_size
            print(f"{font}: {before / 1024 / 1024:.2f} MB -> {after / 1024 / 1024:.2f} MB")
            output.replace(source)
    finally:
        charset_file.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
