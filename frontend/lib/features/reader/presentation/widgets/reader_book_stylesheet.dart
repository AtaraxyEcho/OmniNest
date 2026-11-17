import 'dart:ui' show TextAlign;

import 'package:html/dom.dart' as dom;

/// 一本书的样式表在阅读器里能够表达出来的排版意图。
///
/// 只保留白名单属性，且一律折算成**相对量**（字数、倍率），不落像素：字号由用户
/// 决定，书的像素值只有换算成倍率才能在用户的字号下保持比例。字段为 null 表示
/// 这本书对这个属性没有表达，交给阅读器默认档。
class ParagraphStyleSpec {
  const ParagraphStyleSpec({
    this.firstLineIndentChars,
    this.paragraphSpacingScale,
    this.topMarginScale,
    this.paragraphBlankGapLines,
    this.lineHeightScale,
    this.textAlign,
  });

  /// 首行缩进的全角空格个数。缩进由注入的整字空格实现，因此用字数而非 em：
  /// CJK 下 `2em` 不保证正好两个字，字数天然对齐整字。
  final int? firstLineIndentChars;

  /// 段落尾间距相对正文字号的倍率，来自 `margin-bottom`。
  final double? paragraphSpacingScale;

  /// 段前留白相对正文字号的倍率，来自 `margin-top`。
  ///
  /// 只给靠上边距分段的书用（pgdp 的 `p { margin-top: 1em; margin-bottom: 0 }`
  /// 并写明"use only top-margin for spacing"），解析期折进前一段的尾间距后即失效。
  /// 阅读器侧没有"前间距"这一份额度，两侧各算一份就会重复。
  final double? topMarginScale;

  /// 源文本在这一段前留下的空白行数（TXT 与裸文本用空行分段时的那一型）。
  ///
  /// 这是书自己留的白，但它是**行数**不是像素：折算给阅读器时按
  /// `行数 × 读者的行高` 花段距那一份额度，同样记在前一段的尾部（口径与
  /// `margin-top` 的折算一致），且只在「跟随原书排版」打开时被采纳。
  /// 解析层不读用户行高，所以这里存原始行数而不是倍率。
  final int? paragraphBlankGapLines;

  /// 本书在这一段表达过的行高相对基准行高的倍率，来自 `line-height`。
  ///
  /// 存倍率而不是行高：读者的行距设置不能被书顶掉，只能在读者的行距上再乘这一份。
  /// null 表示这本书没说。
  final double? lineHeightScale;

  /// 书表达的对齐方式。
  final TextAlign? textAlign;

  bool get isEmpty =>
      firstLineIndentChars == null &&
      paragraphSpacingScale == null &&
      topMarginScale == null &&
      paragraphBlankGapLines == null &&
      lineHeightScale == null &&
      textAlign == null;

  /// 合并段落块时判断两个段落能否共处一块：缩进按行生效可以混，段距与对齐是
  /// 块级的，两侧不同就必须另起一块。
  ///
  /// 空白行留白**不在**这里比：它挂在每一行的样式上，同一段的软换行续行天然是 0，
  /// 比进来会把一段折行的正文从中间剪开。切块由合并阶段的显式判据做。
  static bool sameBlockLayout(ParagraphStyleSpec? a, ParagraphStyleSpec? b) =>
      a?.paragraphSpacingScale == b?.paragraphSpacingScale &&
      a?.topMarginScale == b?.topMarginScale &&
      a?.lineHeightScale == b?.lineHeightScale &&
      a?.textAlign == b?.textAlign;

  /// 本实例（层叠较高的一层）覆盖 [lower]（较低的一层）后合成的样式。
  ParagraphStyleSpec overlay(ParagraphStyleSpec? lower) {
    if (lower == null) return this;
    return ParagraphStyleSpec(
      firstLineIndentChars: firstLineIndentChars ?? lower.firstLineIndentChars,
      paragraphSpacingScale:
          paragraphSpacingScale ?? lower.paragraphSpacingScale,
      topMarginScale: topMarginScale ?? lower.topMarginScale,
      paragraphBlankGapLines:
          paragraphBlankGapLines ?? lower.paragraphBlankGapLines,
      lineHeightScale: lineHeightScale ?? lower.lineHeightScale,
      textAlign: textAlign ?? lower.textAlign,
    );
  }
}

/// 从书的样式表文本与元素内联 `style` 解析出受限层叠结果。
///
/// 参照主流阅读器的三段层叠（作者样式 → 阅读器样式 → 用户样式）里的作者段：
/// 这里只实现 CSS 2.1 的一个子集——复合选择器与后代组合器、白名单声明，
/// 其余属性直接丢弃。声明的取胜顺序是 `!important` → (id, class, 类型) 特异性 →
/// 源序，与规范一致；唯一的边界是内联 `style` 不参与这场比较，它总是压过样式表
/// （CSS 里作者的 `!important` 应当压过普通内联声明，白名单没有会这样写的场景）。
class BookStyleSheet {
  BookStyleSheet._(this._rules, this._referenceFontSize, this.ruleCount);

  /// 书没有提供任何样式表时的空表：所有查询都返回未表达。
  BookStyleSheet.empty()
    : _rules = const [],
      _referenceFontSize = defaultReferenceFontSize,
      ruleCount = 0;

  /// CSS 的初始字号，用于把书里以像素表达的排版量折成倍率。
  static const double defaultReferenceFontSize = 16.0;

  /// 单份样式表的字符上限：超出即截断，畸形或巨型样式表不能拖慢整章解析。
  static const int maxCssCharacters = 512 * 1024;

  /// 规则与单条声明数量上限，防御 `a{}a{}...` 型构造。
  static const int maxRules = 2000;
  static const int maxDeclarationsPerRule = 100;
  static const int maxSelectorCharacters = 256;

  /// 缩进与间距的合理区间：超出视为样式表噪声，按边界收敛。
  static const int maxIndentChars = 4;
  static const double maxSpacingScale = 4.0;

  /// `line-height` 的可信区间与折算基准。
  ///
  /// 基准取稿子正文的行距档：书的行高只有相对这个档才有"层次"可言
  /// （`p { line-height: 130% }` 比基准窄，`2` 比基准宽）。
  static const double baseBookLineHeight = 1.35;
  static const double minBookLineHeight = 0.9;
  static const double maxBookLineHeight = 3.0;
  static const double minLineHeightScale = 0.85;
  static const double maxLineHeightScale = 1.8;

  final List<_Rule> _rules;
  final double _referenceFontSize;
  final int ruleCount;

  /// 解析一段（可能多份拼接的）CSS 文本。
  ///
  /// 无法识别的构造按丢弃处理而不是抛错：解析失败降级到阅读器默认档是本模块的
  /// 不变量，一本样式表写坏的书不应该让阅读页报错。
  factory BookStyleSheet.parse(String css) {
    final source =
        css.length > maxCssCharacters
            ? css.substring(0, maxCssCharacters)
            : css;
    final stripped = _stripComments(source);
    var reference = defaultReferenceFontSize;
    final rules = <_Rule>[];
    var cursor = 0;
    while (cursor < stripped.length && rules.length < maxRules) {
      var brace = stripped.indexOf('{', cursor);
      if (brace < 0) break;
      // 先跳过分号结尾的语句（@charset/@namespace/@import 与残留的空声明）：真实
      // 样式表基本都以它们开头，若把"到下一个 { 之前"整个当选择器读，第一条真规则
      // 会被连头吞掉。
      var semicolon = stripped.indexOf(';', cursor);
      while (semicolon >= 0 && semicolon < brace) {
        cursor = semicolon + 1;
        brace = stripped.indexOf('{', cursor);
        if (brace < 0) break;
        semicolon = stripped.indexOf(';', cursor);
      }
      if (brace < 0) break;
      final prelude = stripped.substring(cursor, brace).trim();
      final end = _matchingBrace(stripped, brace);
      if (end < 0) break;
      cursor = end + 1;
      if (prelude.startsWith('@')) {
        // @media/@page/@font-face 在本子集里不支持；其块内容随块一起丢弃。
        continue;
      }
      final declarations = _parseDeclarations(
        stripped.substring(brace + 1, end),
      );
      if (declarations.isEmpty) continue;
      for (final selector in prelude.split(',')) {
        // 上限要在内层也判：一条选择器列表能一次展开出任意多条规则，
        // 只靠外层 while 的条件等于没设限（`p,p,...×200000` 实测产出 20 万条）。
        if (rules.length >= maxRules) break;
        final parsed = _SelectorSequence.tryParse(selector);
        if (parsed == null) continue;
        // `html`/`body` 上声明的 font-size 是书自己的像素基准，后面的 em/px
        // 换算都以它为参照；只有这一个属性在解析阶段就要读一遍。
        final rootSize =
            parsed.isRootTypeSelector
                ? _fontSizePixels(declarations['font-size']?.value, reference)
                : null;
        if (rootSize != null) reference = rootSize;
        rules.add(
          _Rule(
            selector: parsed,
            declarations: declarations,
            order: rules.length,
          ),
        );
      }
    }
    return BookStyleSheet._(rules, reference, rules.length);
  }

  /// 取某个元素的书样式：内联 `style` 覆盖样式表结果，`text-align` 与 `text-indent`
  /// 沿祖先继承。
  ///
  /// 元素没有 class、id 也不在任何匹配规则里、祖先也没表达过时返回 null，
  /// 表示这本书对它的排版没有任何意图。
  ParagraphStyleSpec? styleFor(dom.Element element) {
    final own = _ownStyle(element);
    if (own?.textAlign != null && own?.firstLineIndentChars != null) {
      return own;
    }
    final inherited = _inheritedFromAncestors(element);
    final merged = ParagraphStyleSpec(
      firstLineIndentChars:
          own?.firstLineIndentChars ?? inherited.firstLineIndentChars,
      // 段距是 margin 折算来的，margin 不继承，只能带元素自己那一份。
      paragraphSpacingScale: own?.paragraphSpacingScale,
      topMarginScale: own?.topMarginScale,
      // 行高是 `line-height` 折算来的相对倍率，与字号同族可继承；但 margin 那两份不继承，
      // 这里同样只带元素自己那一份。
      lineHeightScale: own?.lineHeightScale,
      textAlign: own?.textAlign ?? inherited.textAlign,
    );
    return merged.isEmpty ? null : merged;
  }

  /// 白名单里两个可继承属性最近的祖先取值（CSS 2.1：`text-align` 与 `text-indent`
  /// 都是 Inherited: yes）。
  ///
  /// `text-indent` 必须继承：绝大多数中文书的缩进写在 `body` 或包裹 `div` 上
  /// （真书证据：Kindle 导出的 style0002.css 就一条 `body { text-indent: 2em }`），
  /// 把它当不可继承属性等于整本书的缩进查不到出处，「跟随原书」便无从生效。
  /// `margin` 规范上不继承，留在元素自己身上，否则父级的块间距会落到每个子段落。
  ParagraphStyleSpec _inheritedFromAncestors(dom.Element element) {
    TextAlign? align;
    int? indent;
    dom.Node? parent = element.parent;
    while (parent is dom.Element && (align == null || indent == null)) {
      final style = _ownStyle(parent);
      if (style != null) {
        align ??= style.textAlign;
        indent ??= style.firstLineIndentChars;
      }
      parent = parent.parent;
    }
    return ParagraphStyleSpec(firstLineIndentChars: indent, textAlign: align);
  }

  /// 一次章节解析内共享元素的查询结果：子元素找继承时会反复走到同一个祖先，
  /// 每条规则都要重跑一遍命中与比特异性没有道理。样式表随解析一起作废。
  final Map<dom.Element, ParagraphStyleSpec?> _ownMemo = {};

  /// 元素**自己**的表达：内联 `style` 压过样式表，不含任何继承。
  ParagraphStyleSpec? _ownStyle(dom.Element element) {
    if (_ownMemo.containsKey(element)) return _ownMemo[element];
    final sheet = _resolveSheetStyle(element);
    final inline = _parseDeclarations(element.attributes['style'] ?? '');
    var result = inline.isEmpty ? sheet : _specFrom(inline).overlay(sheet);
    if (result != null && result.isEmpty) result = null;
    _ownMemo[element] = result;
    return result;
  }

  /// 按**属性逐个**层叠，而不是整条规则取胜：`.first { text-indent: 2em }` 与
  /// `p { margin-bottom: 1em }` 必须同时生效，这是 CSS 的基本语义，选择器命中集
  /// 也从来不是互斥的。
  ParagraphStyleSpec? _resolveSheetStyle(dom.Element element) {
    if (_rules.isEmpty) return null;
    final chain = _ancestorChain(element);
    final winners = <String, _Declaration>{};
    final priorities = <String, _Priority>{};
    for (final rule in _rules) {
      if (!rule.selector.matches(chain)) continue;
      rule.declarations.forEach((key, value) {
        final priority = _Priority(
          important: value.important,
          specificity: rule.selector.specificity,
          order: rule.order,
        );
        final previous = priorities[key];
        // 取胜顺序是 important → 特异性 → 源序：只比特异性会让
        // `p { margin-bottom: 2em !important }` 输给后写的 `.box p { margin-bottom: 0 }`。
        if (previous == null || priority.compareTo(previous) > 0) {
          winners[key] = value;
          priorities[key] = priority;
        }
      });
    }
    if (winners.isEmpty) return null;
    return _specFrom(winners);
  }

  /// 元素到根的 (tag, id, classes) 链，供后代组合器从右往左匹配。
  static List<_ElementFace> _ancestorChain(dom.Element element) {
    final chain = <_ElementFace>[];
    dom.Node? node = element;
    while (node is dom.Element) {
      chain.add(_ElementFace.of(node));
      node = node.parent;
    }
    return chain;
  }

  /// 把白名单声明折算成 [ParagraphStyleSpec]。
  ParagraphStyleSpec _specFrom(Map<String, _Declaration> declarations) {
    return ParagraphStyleSpec(
      firstLineIndentChars: _indentChars(declarations['text-indent']?.value),
      paragraphSpacingScale: _spacingScale(
        declarations['margin-bottom']?.value,
      ),
      topMarginScale: _spacingScale(declarations['margin-top']?.value),
      lineHeightScale: _lineHeightScale(declarations['line-height']?.value),
      textAlign: _align(declarations['text-align']?.value),
    );
  }

  /// 把长度折算成正文字号倍率，支持 em/rem/% 与以参考字号折算的绝对单位。
  double? _scale(String? value) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty || text == 'auto') return null;
    if (text.endsWith('%')) {
      final percent = double.tryParse(text.substring(0, text.length - 1));
      return percent == null ? null : percent / 100.0;
    }
    final number = double.tryParse(text.replaceAll(RegExp(r'[a-z]+$'), ''));
    if (number == null) return null;
    if (text.endsWith('em') || text.endsWith('rem')) return number;
    if (text.endsWith('px')) return number / _referenceFontSize;
    if (text.endsWith('pt')) return number * (96.0 / 72.0) / _referenceFontSize;
    if (text.endsWith('pc')) return number * (16.0 / 12.0) / _referenceFontSize;
    if (RegExp(r'^-?[0-9.]+$').hasMatch(text)) return number;
    return null;
  }

  int? _indentChars(String? value) {
    if (value == null) return null;
    if (value.trim().toLowerCase() == 'none') return 0;
    final scale = _scale(value);
    if (scale == null) return null;
    if (scale <= 0) return 0;
    return scale.round().clamp(0, maxIndentChars);
  }

  /// 把 `line-height` 折成相对阅读器基准行高的倍率。
  ///
  /// 书里 `1.5`、`150%`、`1.5em` 表达的是同一件事；绝对值超出正常正文行距区间的
  /// 按噪声丢弃，落在区间内的再折算成倍率并钳到"看得出行距层次、又不至于把
  /// 一页挤成两三行"的范围内。
  double? _lineHeightScale(String? value) {
    final scale = _scale(value);
    if (scale == null) return null;
    if (scale < minBookLineHeight || scale > maxBookLineHeight) return null;
    return (scale / baseBookLineHeight).clamp(
      minLineHeightScale,
      maxLineHeightScale,
    );
  }

  double? _spacingScale(String? value) {
    final scale = _scale(value);
    if (scale == null) return null;
    if (scale <= 0) return 0;
    return scale.clamp(0, maxSpacingScale);
  }

  static TextAlign? _align(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      'center' => TextAlign.center,
      'justify' => TextAlign.justify,
      'start' || 'end' || 'auto' || 'match-parent' => null,
      _ => null,
    };
  }

  /// 把 `html`/`body` 上的字号折成像素基准。
  ///
  /// 相对单位按**当前累积**的基准换算，所以 `html{200%} body{80%}` 会像 CSS 那样
  /// 组合成 1.6 倍，而不是各自独立地回到 16px。单位必须先随正则一起取出来：
  /// 先剥字母再解析数字的写法会把 `120%` 留在串里，解析失败后 `%` 分支永远进不去。
  static double? _fontSizePixels(String? value, double reference) {
    final text = value?.trim().toLowerCase();
    if (text == null || text.isEmpty) return null;
    final match = _fontSizePattern.firstMatch(text);
    if (match == null) return null;
    final number = double.tryParse(match.group(1)!);
    if (number == null || number <= 0) return null;
    return switch (match.group(2)) {
      'px' => number,
      'pt' => number * (96.0 / 72.0),
      'pc' => number * (16.0 / 12.0),
      '%' => number / 100.0 * reference,
      'em' || 'rem' => number * reference,
      _ => null,
    };
  }

  /// 解析一条规则或一个内联 `style` 的声明，只留白名单里的属性。
  ///
  /// 计数按"命中白名单的声明"走，包括折算后被丢弃的那些：只在存表时自增的话，
  /// 一万条 `margin` 就能绕过单条规则的声明上限。
  static Map<String, _Declaration> _parseDeclarations(String body) {
    final result = <String, _Declaration>{};
    var count = 0;
    for (final part in body.split(';')) {
      final colon = part.indexOf(':');
      if (colon <= 0) continue;
      final name = part.substring(0, colon).trim().toLowerCase();
      if (!_whitelistedProperties.contains(name)) continue;
      if (++count > maxDeclarationsPerRule) break;
      var value = part.substring(colon + 1).trim();
      var important = false;
      if (value.endsWith('!important')) {
        important = true;
        value = value.substring(0, value.length - '!important'.length).trim();
      }
      if (value.isEmpty) continue;
      if (name == 'margin' || name == 'margin-bottom' || name == 'margin-top') {
        // 简写同时给出上、下两个留白，两边都要取：只认 bottom 的话，靠 top 分段
        // 的书（pgdp 原文注释"use only top-margin for spacing"）段距折成 0。
        final bottom = switch (name) {
          'margin-bottom' => value,
          'margin-top' => null,
          _ => _marginBottomOf(value),
        };
        final top = switch (name) {
          'margin-top' => value,
          'margin-bottom' => null,
          _ => _marginTopOf(value),
        };
        if (bottom != null) {
          result['margin-bottom'] = _Declaration(bottom, important: important);
        }
        if (top != null) {
          result['margin-top'] = _Declaration(top, important: important);
        }
        continue;
      }
      result[name] = _Declaration(value, important: important);
    }
    return result;
  }

  /// `margin` 简写取下外边距：两值是"纵 横"，三/四值的第三个是下边。
  static String? _marginBottomOf(String value) {
    final parts = value.split(RegExp(r'\s+'));
    return switch (parts.length) {
      1 => parts.first,
      2 => parts.first,
      3 => parts[2],
      4 => parts[2],
      _ => null,
    };
  }

  /// `margin` 简写取上外边距：一到四值的第一个都是上边。
  static String? _marginTopOf(String value) {
    final parts = value.split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.length > 4) return null;
    return parts.first;
  }

  static const _whitelistedProperties = {
    'text-indent',
    'margin',
    'margin-bottom',
    'margin-top',
    'text-align',
    'font-size',
    // 17/17 本实测语料都在样式表里写了行距；不在白名单里就等于这本书的行高
    // 层次在"跟随书籍样式"和默认档两头上一起丢失。
    'line-height',
  };

  /// 字号字面量：数字加一个单位。`%` 不是字母，所以不能靠"剥掉结尾字母"反推单位。
  static final RegExp _fontSizePattern = RegExp(
    r'^([0-9]*\.?[0-9]+)(px|pt|pc|em|rem|%)$',
  );

  static String _stripComments(String css) {
    final buffer = StringBuffer();
    var index = 0;
    while (index < css.length) {
      final open = css.indexOf('/*', index);
      if (open < 0) {
        buffer.write(css.substring(index));
        break;
      }
      buffer.write(css.substring(index, open));
      final close = css.indexOf('*/', open + 2);
      if (close < 0) break;
      index = close + 2;
    }
    return buffer.toString();
  }

  /// 返回与 [openIndex] 处 `{` 配对的 `}` 下标。
  ///
  /// at 规则块内部还能再套规则块（`@media screen { p { … } }`），必须按深度配对：
  /// 取第一个 `}` 会把剩下的 `}` 当成一条选择器的开头，后续规则一起被带偏。
  static int _matchingBrace(String css, int openIndex) {
    var depth = 0;
    for (var index = openIndex; index < css.length; index++) {
      final unit = css.codeUnitAt(index);
      if (unit == 0x7B) {
        depth++;
      } else if (unit == 0x7D) {
        depth--;
        if (depth == 0) return index;
      }
    }
    return -1;
  }
}

/// 一条已解析规则：选择器序列、其声明表，以及它在样式表里的书写次序。
///
/// 次序是层叠的最后一档：特异性相同后写的胜出，所以它必须随规则一起存下来，
/// 不能靠列表下标现取——同一份声明表会被多条选择器共享。
class _Rule {
  _Rule({
    required this.selector,
    required this.declarations,
    required this.order,
  });

  final _SelectorSequence selector;
  final Map<String, _Declaration> declarations;
  final int order;
}

/// 一条白名单声明：值，以及作者有没有把它标成 `!important`。
class _Declaration {
  const _Declaration(this.value, {this.important = false});

  final String value;
  final bool important;
}

/// 一条声明在这一层里的取胜依据，按 CSS 的顺序逐项比较。
class _Priority {
  const _Priority({
    required this.important,
    required this.specificity,
    required this.order,
  });

  final bool important;
  final _Specificity specificity;
  final int order;

  int compareTo(_Priority other) {
    if (important != other.important) return important ? 1 : -1;
    final bySpecificity = specificity.compareTo(other.specificity);
    if (bySpecificity != 0) return bySpecificity;
    return order.compareTo(other.order);
  }
}

/// 元素用于选择器匹配的三元组。
class _ElementFace {
  const _ElementFace({
    required this.tag,
    required this.id,
    required this.classes,
  });

  factory _ElementFace.of(dom.Element element) {
    final classAttribute = element.attributes['class'] ?? '';
    return _ElementFace(
      tag: (element.localName ?? '').toLowerCase(),
      id: element.id.isEmpty ? null : element.id,
      classes:
          classAttribute
              .split(RegExp(r'\s+'))
              .where((part) => part.isNotEmpty)
              .toSet(),
    );
  }

  final String tag;
  final String? id;
  final Set<String> classes;
}

/// 选择器序列：由若干复合选择器按后代组合器（空格）连接。
///
/// 只支持复合选择器与后代组合器；`>`、`+`、`~` 与伪类出现即整条放弃，
/// 因为按近似匹配套用会把样式落到不该落的元素上。
class _SelectorSequence {
  const _SelectorSequence({
    required this.compounds,
    required this.specificity,
    required this.isRootTypeSelector,
  });

  /// 从左到右排列的复合选择器，最后一个是要匹配在元素自身上的那一段。
  final List<_Compound> compounds;
  final _Specificity specificity;

  /// `html`/`body` 单独成一条选择器：只有它能提供像素参考字号。
  final bool isRootTypeSelector;

  static _SelectorSequence? tryParse(String selector) {
    final text = selector.trim();
    if (text.isEmpty || text.length > BookStyleSheet.maxSelectorCharacters) {
      return null;
    }
    if (text.contains('>') ||
        text.contains('+') ||
        text.contains('~') ||
        text.contains(':') ||
        text.contains('[') ||
        text.contains('*')) {
      return null;
    }
    final parts = text.split(RegExp(r'\s+'));
    final compounds = <_Compound>[];
    var ids = 0;
    var classes = 0;
    var tags = 0;
    for (final part in parts) {
      final compound = _Compound.tryParse(part);
      if (compound == null) return null;
      ids += compound.idCount;
      classes += compound.classCount;
      tags += compound.tagCount;
      compounds.add(compound);
    }
    final isRoot =
        compounds.length == 1 &&
        compounds.single.tag != null &&
        compounds.single.classCount == 0 &&
        compounds.single.idCount == 0 &&
        (compounds.single.tag == 'html' || compounds.single.tag == 'body');
    return _SelectorSequence(
      compounds: compounds,
      specificity: _Specificity(ids, classes, tags),
      isRootTypeSelector: isRoot,
    );
  }

  /// [chain] 由元素自身开始向根排列；从右往左按后代语义逐段消耗。
  ///
  /// 最右一段必须命中元素自身：那才是这条选择器要落的元素。允许它落在祖先上等于
  /// 把 `margin` 与 `text-indent` 变成可继承属性，祖先的高特异性还会压过元素自己
  /// 的声明（`.box { text-indent: 0 }` 赢过 `p { text-indent: 1em }`）。对齐的继承
  /// 只走 `styleFor` 里的 `_inheritedAlign`，与这张 winners 表无关。
  bool matches(List<_ElementFace> chain) {
    if (chain.isEmpty) return false;
    if (!compounds.last.matches(chain.first)) return false;
    var chainIndex = 1;
    for (var step = compounds.length - 2; step >= 0; step--) {
      final compound = compounds[step];
      var matched = false;
      while (chainIndex < chain.length) {
        if (compound.matches(chain[chainIndex])) {
          matched = true;
          chainIndex++;
          break;
        }
        chainIndex++;
      }
      if (!matched) return false;
    }
    return true;
  }
}

/// 复合选择器：`p.chapter#intro` 这类 tag/class/id 的合取。
class _Compound {
  const _Compound({
    this.tag,
    this.id,
    this.classes = const [],
    required this.idCount,
    required this.classCount,
    required this.tagCount,
  });

  final String? tag;
  final String? id;
  final List<String> classes;
  final int idCount;
  final int classCount;
  final int tagCount;

  static _Compound? tryParse(String text) {
    if (text.isEmpty) return null;
    String? tag;
    String? id;
    final classNames = <String>[];
    var index = 0;
    final tagMatch = RegExp(r'^[a-zA-Z][a-zA-Z0-9]*').firstMatch(text);
    if (tagMatch != null) {
      tag = tagMatch.group(0)!.toLowerCase();
      index = tagMatch.end;
    }
    var ids = 0;
    while (index < text.length) {
      final rest = text.substring(index);
      if (rest.startsWith('#')) {
        final match = RegExp(r'^#[a-zA-Z0-9_-]+').firstMatch(rest);
        if (match == null) return null;
        id = match.group(0)!.substring(1);
        ids++;
        index += match.end;
        continue;
      }
      if (rest.startsWith('.')) {
        final match = RegExp(r'^\.[a-zA-Z0-9_-]+').firstMatch(rest);
        if (match == null) return null;
        classNames.add(match.group(0)!.substring(1));
        index += match.end;
        continue;
      }
      return null;
    }
    return _Compound(
      tag: tag,
      id: id,
      classes: classNames,
      idCount: ids,
      classCount: classNames.length,
      tagCount: tag == null ? 0 : 1,
    );
  }

  bool matches(_ElementFace face) {
    if (tag != null && face.tag != tag) return false;
    if (id != null && face.id != id) return false;
    for (final className in classes) {
      if (!face.classes.contains(className)) return false;
    }
    return true;
  }
}

/// CSS 2.1 的 (id, class, 类型) 三元组特异性。
class _Specificity {
  const _Specificity(this.ids, this.classes, this.tags);

  final int ids;
  final int classes;
  final int tags;

  int compareTo(_Specificity other) {
    if (ids != other.ids) return ids.compareTo(other.ids);
    if (classes != other.classes) return classes.compareTo(other.classes);
    return tags.compareTo(other.tags);
  }
}
