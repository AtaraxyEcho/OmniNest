/// 不受信 HTML 的定界扫描。
///
/// 惰性量词正则（`.*?`、`[^>]*?`、`[^>]*`）在畸形正文上退化成二次方：800K 字符的
/// 章节实测 16 到 33 秒，而且都跑在渲染 isolate 上。这里每个扫描只向前推进游标，
/// 代价与文本长度成正比。
///
/// 所有位置都是原串下标：`toLowerCase()` 对个别字符（如 U+0130）会改变长度，
/// 整串小写之后拿到的下标不能直接用于切片，所以比较一律逐字符大小写折叠。
class HtmlAttribute {
  const HtmlAttribute({
    required this.name,
    required this.start,
    required this.end,
    required this.value,
  });

  /// 小写属性名。
  final String name;

  /// 属性整段在原串中的起点，指向名字的首字符。
  final int start;

  /// 属性整段在原串中的终点（不含），带引号时含闭引号；可整段替换。
  final int end;

  /// 属性值；无值属性为空串。
  final String value;
}

/// 一个开标签，`[start, end)` 覆盖 `<name ...>` 整段。
class HtmlTag {
  const HtmlTag({
    required this.name,
    required this.start,
    required this.end,
    required this.attributes,
  });

  /// 小写标签名。
  final String name;

  final int start;
  final int end;

  /// 同名属性只保留第一次出现，与 HTML 解析规则一致。
  final Map<String, HtmlAttribute> attributes;

  HtmlAttribute? attribute(String name) => attributes[name];

  String? attributeValue(String name) => attributes[name]?.value;
}

/// 一段区间，`[start, end)`。
class HtmlRange {
  const HtmlRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;
}

/// 按书写顺序找出名为 [names] 之一的开标签。
///
/// 标签以第一个不在属性值引号内的 `>` 结束：`<img alt="a > b" src="1.jpg">` 这类
/// 合法标签如果在 `alt` 处就截断，`src` 会整个丢掉，图片再也提不出来。
/// `<!-- -->` 注释里的标签名不算标签，注释整段跳过。
/// 文本中再没有 `>` 时后面的标签都无法定界，直接停止。
List<HtmlTag> scanHtmlTags(String html, Set<String> names) {
  final out = <HtmlTag>[];
  var cursor = 0;
  while (true) {
    final lt = _nextTagOpen(html, cursor);
    if (lt < 0) {
      break;
    }
    final name = _tagNameAt(html, lt + 1);
    if (name.isEmpty || !names.contains(name)) {
      cursor = lt + 1;
      continue;
    }
    final gt = _findTagCloseGt(html, lt + 1);
    if (gt < 0) {
      break;
    }
    out.add(
      HtmlTag(
        name: name,
        start: lt,
        end: gt + 1,
        attributes: _parseAttributes(html, lt + 1 + name.length, gt + 1),
      ),
    );
    cursor = gt + 1;
  }
  return out;
}

/// 按书写顺序找出所有 `<...>` 标签的区间，供整段替换使用。
List<HtmlRange> scanHtmlTagRanges(String html) {
  final out = <HtmlRange>[];
  var cursor = 0;
  while (true) {
    final lt = _nextTagOpen(html, cursor);
    if (lt < 0) {
      break;
    }
    final gt = _findTagCloseGt(html, lt + 1);
    if (gt < 0) {
      break;
    }
    out.add(HtmlRange(lt, gt + 1));
    cursor = gt + 1;
  }
  return out;
}

/// 按书写顺序找出 `[start, end)` 覆盖开标签到闭合标签的元素区间。
///
/// 未闭合的元素延伸到文本末尾：RAWTEXT 元素（`style`、`script`）读到 EOF 时
/// 浏览器同样不渲染其内容，把整段留在正文里只会让朗读念出 CSS。
List<HtmlRange> scanHtmlElementRanges(String html, Set<String> names) {
  final out = <HtmlRange>[];
  var cursor = 0;
  while (true) {
    // 注释里的 `<style>` 不是元素：不跳过的话找不到 `</style>` 会把注释起到
    // 章节末尾的整段正文当成样式块删空。
    final lt = _nextTagOpen(html, cursor);
    if (lt < 0) {
      break;
    }
    final name = _tagNameAt(html, lt + 1);
    if (name.isEmpty || !names.contains(name)) {
      cursor = lt + 1;
      continue;
    }
    final closeEnd = _closeTagEnd(html, name, lt + 1);
    if (closeEnd == null) {
      out.add(HtmlRange(lt, html.length));
      break;
    }
    out.add(HtmlRange(lt, closeEnd));
    cursor = closeEnd;
  }
  return out;
}

/// 依 [ranges] 用 [replacement] 顶替对应区间；区间必须互不重叠且升序。
String replaceHtmlRanges(
  String html,
  List<HtmlRange> ranges,
  String replacement,
) {
  if (ranges.isEmpty) {
    return html;
  }
  final buffer = StringBuffer();
  var cursor = 0;
  for (final range in ranges) {
    buffer.write(html.substring(cursor, range.start));
    buffer.write(replacement);
    cursor = range.end;
  }
  buffer.write(html.substring(cursor));
  return buffer.toString();
}

/// 查找下一个不是注释起始的 `<`；`<!-- ... -->` 整段跳过。
///
/// 没有下一个标签时返回 -1，包括注释未闭合的情况——此后已无边界可依。
int _nextTagOpen(String html, int from) {
  var cursor = from;
  while (true) {
    final lt = html.indexOf('<', cursor);
    if (lt < 0) {
      return -1;
    }
    if (html.startsWith('<!--', lt)) {
      final commentEnd = html.indexOf('-->', lt + 4);
      if (commentEnd < 0) {
        return -1;
      }
      cursor = commentEnd + 3;
      continue;
    }
    return lt;
  }
}

/// 在开标签内查找闭合 `>` 的下标；成对单/双引号内部的 `>` 不算结束符。
int _findTagCloseGt(String html, int from) {
  var quote = 0;
  for (var i = from; i < html.length; i++) {
    final unit = html.codeUnitAt(i);
    if (quote != 0) {
      if (unit == quote) {
        quote = 0;
      }
    } else if (unit == _dquote || unit == _squote) {
      quote = unit;
    } else if (unit == _gt) {
      return i;
    }
  }
  return -1;
}

/// 读取 `<` 之后的 ASCII 标签名并小写返回；不是标签名时返回空串。
///
/// 名字后面必须紧跟空白、`/` 或 `>`，否则 `<style-x>` 这类会被误认成 `style`。
String _tagNameAt(String html, int from) {
  var i = from;
  while (i < html.length && _isNameUnit(html.codeUnitAt(i))) {
    i++;
  }
  if (i == from) {
    return '';
  }
  if (i < html.length &&
      !_isHtmlSpace(html.codeUnitAt(i)) &&
      html.codeUnitAt(i) != _slash &&
      html.codeUnitAt(i) != _gt) {
    return '';
  }
  return html.substring(from, i).toLowerCase();
}

/// 查找下一个不是注释起始的 `</`。
int _nextCloseTagOpen(String html, int from) {
  var cursor = from;
  while (true) {
    final lt = html.indexOf('</', cursor);
    if (lt < 0) {
      return -1;
    }
    if (html.startsWith('<!--', lt)) {
      final commentEnd = html.indexOf('-->', lt + 4);
      if (commentEnd < 0) {
        return -1;
      }
      cursor = commentEnd + 3;
      continue;
    }
    return lt;
  }
}

/// 找 `</name>`，要求名字后只允许空白并紧跟 `>`；返回闭标签之后的下标。
///
/// 找不到时返回 null，表示这个元素没有闭合。
int? _closeTagEnd(String html, String name, int from) {
  var cursor = from;
  while (true) {
    final lt = _nextCloseTagOpen(html, cursor);
    if (lt < 0) {
      return null;
    }
    final nameStart = lt + 2;
    if (_tagNameAt(html, nameStart) == name) {
      var i = _skipSpaces(html, nameStart + name.length, html.length);
      if (i < html.length && html.codeUnitAt(i) == _gt) {
        return i + 1;
      }
    }
    cursor = nameStart;
  }
}

/// 解析 `[from, tagEnd)` 内的属性；`tagEnd` 指向闭 `>` 之后。
Map<String, HtmlAttribute> _parseAttributes(String html, int from, int tagEnd) {
  final out = <String, HtmlAttribute>{};
  var i = from;
  while (i < tagEnd) {
    i = _skipSpaces(html, i, tagEnd);
    if (i >= tagEnd) {
      break;
    }
    final unit = html.codeUnitAt(i);
    if (unit == _slash || unit == _gt) {
      i++;
      continue;
    }
    final nameStart = i;
    while (i < tagEnd) {
      final c = html.codeUnitAt(i);
      if (_isHtmlSpace(c) || c == _eq || c == _slash || c == _gt) {
        break;
      }
      i++;
    }
    final name = html.substring(nameStart, i).toLowerCase();
    i = _skipSpaces(html, i, tagEnd);
    if (i >= tagEnd || html.codeUnitAt(i) != _eq) {
      out.putIfAbsent(
        name,
        () => HtmlAttribute(name: name, start: nameStart, end: i, value: ''),
      );
      continue;
    }
    i = _skipSpaces(html, i + 1, tagEnd);
    final quote = i < tagEnd ? html.codeUnitAt(i) : 0;
    if (quote == _dquote || quote == _squote) {
      final valueStart = i + 1;
      var valueEnd = valueStart;
      while (valueEnd < tagEnd && html.codeUnitAt(valueEnd) != quote) {
        valueEnd++;
      }
      final end = valueEnd < tagEnd ? valueEnd + 1 : valueEnd;
      out.putIfAbsent(
        name,
        () => HtmlAttribute(
          name: name,
          start: nameStart,
          end: end,
          value: html.substring(valueStart, valueEnd),
        ),
      );
      i = end;
      continue;
    }
    // 未加引号的值：读到空白或闭 `>` 为止（`>` 必须停，否则属性值会把标签尾巴吃掉），
    // 并且要整段吃掉，否则值会被当成下一个属性名。
    final valueStart = i;
    while (i < tagEnd &&
        !_isHtmlSpace(html.codeUnitAt(i)) &&
        html.codeUnitAt(i) != _gt) {
      i++;
    }
    out.putIfAbsent(
      name,
      () => HtmlAttribute(
        name: name,
        start: nameStart,
        end: i,
        value: html.substring(valueStart, i),
      ),
    );
  }
  return out;
}

int _skipSpaces(String html, int from, int limit) {
  var i = from;
  while (i < limit && _isHtmlSpace(html.codeUnitAt(i))) {
    i++;
  }
  return i;
}

const _dquote = 0x22;
const _squote = 0x27;
const _eq = 0x3D;
const _slash = 0x2F;
const _gt = 0x3E;

bool _isNameUnit(int code) =>
    (code >= 0x41 && code <= 0x5A) ||
    (code >= 0x61 && code <= 0x7A) ||
    (code >= 0x30 && code <= 0x39) ||
    code == 0x2D ||
    code == 0x5F ||
    code == 0x3A;

bool _isHtmlSpace(int code) =>
    code == 0x20 || (code >= 0x09 && code <= 0x0D) || code == 0x0B;
