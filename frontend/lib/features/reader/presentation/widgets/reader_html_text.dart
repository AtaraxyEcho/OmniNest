import 'package:omninest/features/reader/domain/reader_html_scan.dart';

/// 从 HTML 中提取纯文本，用于 TTS 等场景。
///
/// 先整段去掉 `style`/`script` 元素：只剥标签会把样式表源码留在纯文本里，
/// 朗读会念出 CSS，正文检索也会命中书的样式规则。
///
/// 两次替换都走定界扫描。旧写法用 `.*?`（dotAll）和 `[^>]*`：正文里 `a < b`
/// 这种没有闭合 `>` 的尖括号会让每个起点扫到串尾，畸形章节把主 isolate 冻几十秒。
String stripHtml(String html) {
  if (html.trim().isEmpty) return '';
  final withoutElements = replaceHtmlRanges(
    html,
    scanHtmlElementRanges(html, const {'style', 'script'}),
    ' ',
  );
  final withoutTags = replaceHtmlRanges(
    withoutElements,
    scanHtmlTagRanges(withoutElements),
    ' ',
  );
  return _decodeHtmlEntities(
    withoutTags.replaceAll(RegExp(r'\s+'), ' ').trim(),
  );
}

/// 具名字实体表：认不出的写法一律原样保留。
const _namedEntities = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&apos;': "'",
  '&nbsp;': ' ',
  '&mdash;': '—',
  '&ndash;': '–',
  '&hellip;': '…',
  '&copy;': '©',
  '&reg;': '®',
  '&trade;': '™',
  '&laquo;': '«',
  '&raquo;': '»',
  '&lsquo;': '‘',
  '&rsquo;': '’',
  '&ldquo;': '“',
  '&rdquo;': '”',
  '&bull;': '•',
  '&deg;': '°',
  '&para;': '¶',
  '&sect;': '§',
  '&middot;': '·',
  '&times;': '×',
  '&divide;': '÷',
  '&plusmn;': '±',
  '&micro;': 'µ',
  '&frac14;': '¼',
  '&frac12;': '½',
  '&frac34;': '¾',
  '&iexcl;': '¡',
  '&iquest;': '¿',
  '&cent;': '¢',
  '&pound;': '£',
  '&yen;': '¥',
  '&euro;': '€',
  '&brvbar;': '¦',
  '&not;': '¬',
  '&macr;': '¯',
  '&acute;': '´',
  '&cedil;': '¸',
  '&ordm;': 'º',
  '&ordf;': 'ª',
  '&lceil;': '⌈',
  '&rceil;': '⌉',
  '&lfloor;': '⌊',
  '&rfloor;': '⌋',
  '&larr;': '←',
  '&rarr;': '→',
  '&uarr;': '↑',
  '&darr;': '↓',
  '&harr;': '↔',
  '&crarr;': '↵',
  '&Prime;': '″',
  '&prime;': '′',
  '&oline;': '‾',
  '&lang;': '⟨',
  '&rang;': '⟩',
  '&loz;': '◊',
  '&spades;': '♠',
  '&clubs;': '♣',
  '&hearts;': '♥',
  '&diams;': '♦',
};

/// 单趟解码：命中的实体换成字符，认不出的（包括数字超出 UTF-16 范围的）原样留着。
///
/// 旧实现按表逐个 `replaceAll`，既把串扫了 68 遍，又会二次解码 ——
/// `&amp;lt;` 本该还原成字面量 `&lt;`，连环保却把它变成 `<`；
/// `&#1114112;` 这类超范围数字还会让 `String.fromCharCode` 直接抛。
String _decodeHtmlEntities(String text) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final amp = text.indexOf('&', i);
    if (amp < 0) {
      buffer.write(text.substring(i));
      return buffer.toString();
    }
    buffer.write(text.substring(i, amp));
    final semicolon = _findEntityEnd(text, amp);
    final decoded = semicolon < 0 ? null : _decodeEntity(text, amp, semicolon);
    if (decoded == null) {
      buffer.write('&');
      i = amp + 1;
      continue;
    }
    buffer.write(decoded);
    i = semicolon + 1;
  }
  return buffer.toString();
}

/// 从 `&` 起找实体的 `;`；名字只允许字母数字和 `#`，遇到别的字符即不是实体。
int _findEntityEnd(String text, int amp) {
  for (var i = amp + 1; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == 0x3B) {
      return i;
    }
    final isNameUnit =
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A) ||
        (unit >= 0x30 && unit <= 0x39) ||
        unit == 0x23;
    if (!isNameUnit) {
      return -1;
    }
  }
  return -1;
}

String? _decodeEntity(String text, int amp, int semicolon) {
  final name = text.substring(amp + 1, semicolon);
  if (name.isEmpty) {
    return null;
  }
  if (name.codeUnitAt(0) == 0x23) {
    final isHex = name.length > 2 && name[1].toLowerCase() == 'x';
    final value = int.tryParse(
      isHex ? name.substring(2) : name.substring(1),
      radix: isHex ? 16 : 10,
    );
    if (value == null || value < 0 || value > 0x10FFFF) {
      return null;
    }
    return String.fromCharCode(value);
  }
  return _namedEntities['&$name;'];
}
