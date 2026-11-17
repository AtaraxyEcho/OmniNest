import 'dart:ui' show TextAlign;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_book_stylesheet.dart';

/// 用一段样式表和一份正文构造元素，走与真实解析链相同的祖先链。
dom.Element elementWith(String bodyHtml, String selector) {
  final document = html_parser.parse('<html><body>$bodyHtml</body></html>');
  final element = document.querySelector(selector);
  if (element == null) {
    throw StateError('夹具元素不存在：$selector');
  }
  return element;
}

ParagraphStyleSpec? specFor(String css, String bodyHtml, String selector) {
  final sheet = BookStyleSheet.parse(css);
  return sheet.styleFor(elementWith(bodyHtml, selector));
}

void main() {
  group('书样式表的受限解析', () {
    test('class 与后代选择器只对命中的元素生效', () {
      const css = '.chapter p { text-indent: 0em; margin-bottom: 1.2em }';
      const body =
          '<div class="chapter"><p id="a">段一</p></div><p id="b">段二</p>';

      final inside = specFor(css, body, '#a');
      expect(inside, isNotNull);
      expect(inside!.firstLineIndentChars, 0);
      expect(inside.paragraphSpacingScale, closeTo(1.2, 0.001));

      final outside = specFor(css, body, '#b');
      expect(outside, isNull, reason: '后代组合器不能把样式泛给同名的其它段落');
    });

    test('最右一段必须命中元素自身，祖先的规则不落到子元素', () {
      // 旧实现允许最右段落在任意祖先上：`.box { text-indent: 0 }` 会命中 .box 里面的
      // p，并把 p 自己的 `text-indent: 1em` 比特异性比下去——等于把 margin 与
      // text-indent 变成可继承属性。真书里 W&P 的 `hgroup.has-h3 { margin-bottom:
      // 3.51em }` 就是这样落到引用内每个段落上的。
      expect(
        specFor(
          'p { text-indent: 1em } .box { text-indent: 0em }',
          '<div class="box"><p>段</p></div>',
          'p',
        )!.firstLineIndentChars,
        1,
        reason: '自身命中的规则优先，祖先的声明管不到子元素',
      );
      expect(
        specFor(
          '.head { margin-bottom: 3.51em } p { margin-bottom: 0em }',
          '<div class="head"><p>段</p></div>',
          'p',
        )!.paragraphSpacingScale,
        closeTo(0.0, 0.001),
      );
      expect(
        specFor(
          'blockquote { margin-bottom: 1em } p { margin-bottom: 0em }',
          '<blockquote><p>段</p></blockquote>',
          'p',
        )!.paragraphSpacingScale,
        closeTo(0.0, 0.001),
        reason: '引用块的下边距不该被里面的段落继承',
      );

      expect(
        specFor(
          '.head p { margin-bottom: 2em }',
          '<div class="head"><p>段</p></div>',
          'p',
        )!.paragraphSpacingScale,
        closeTo(2.0, 0.001),
        reason: '后代组合器照常生效：前面的段是条件，最后一段才是落点',
      );
    });

    test('继承对齐不能抹掉段前留白，规则上限对选择器列表同样生效', () {
      // 书里只要写过任一条继承的 text-align（`body { text-align: justify }` 极常见），
      // styleFor 重建 spec 时漏字段就会让靠 margin-top 分段的整章段距归零。
      final leading =
          specFor(
            'body { text-align: justify } p { margin-top: 1em; margin-bottom: 0 }',
            '<p>段</p>',
            'p',
          )!;
      expect(leading.textAlign, TextAlign.justify);
      expect(
        leading.topMarginScale,
        closeTo(1.0, 0.001),
        reason: '继承对齐只补 textAlign，其余三项必须原样带上',
      );
      expect(leading.paragraphSpacingScale, closeTo(0.0, 0.001));

      final selectorList = List.filled(
        BookStyleSheet.maxRules * 4,
        'p',
      ).join(',');
      final manySelectors = BookStyleSheet.parse(
        '$selectorList { margin-bottom: 1em }',
      );
      expect(
        manySelectors.ruleCount,
        lessThanOrEqualTo(BookStyleSheet.maxRules),
        reason: '一条选择器列表不能一次展开出任意多条规则',
      );
    });

    test('按属性逐个层叠，命中多条规则时各取所长', () {
      const css = '.first { text-indent: 2em } p { margin-bottom: 1em }';
      final spec = specFor(css, '<p class="first">段</p>', 'p');
      expect(spec!.firstLineIndentChars, 2);
      expect(spec.paragraphSpacingScale, closeTo(1.0, 0.001));
    });

    test('class 选择器压过元素选择器，同特异性按源序', () {
      const css = 'p { text-indent: 1em } .flat { text-indent: 0em }';
      expect(
        specFor(css, '<p class="flat">段</p>', 'p')!.firstLineIndentChars,
        0,
      );

      const sameStrength = 'p { text-indent: 1em } p { text-indent: 3em }';
      expect(
        specFor(sameStrength, '<p>段</p>', 'p')!.firstLineIndentChars,
        3,
        reason: '同特异性后写的胜出',
      );

      const idWins = '#one { text-indent: 0em } p { text-indent: 2em }';
      expect(
        specFor(idWins, '<p id="one">段</p>', 'p')!.firstLineIndentChars,
        0,
      );
    });

    test('em/px/pt 与 % 一律折成倍率，像素按书写基准折算', () {
      final spec = specFor(
        'body { font-size: 20px } p { margin-bottom: 20px }',
        '<p>段</p>',
        'p',
      );
      expect(
        spec!.paragraphSpacingScale,
        closeTo(1.0, 0.001),
        reason: '书里 20px 配它自己的 20px 基准，落库必须是倍率 1.0',
      );

      final defaults = specFor(
        'p { margin-bottom: 12pt; text-indent: 24px }',
        '<p>段</p>',
        'p',
      );
      // 12pt = 16px = 参考字号 1em；24px = 1.5em → 2 个整字。
      expect(defaults!.paragraphSpacingScale, closeTo(1.0, 0.001));
      expect(defaults.firstLineIndentChars, 2);

      final percent = specFor('p { margin-bottom: 150% }', '<p>段</p>', 'p');
      expect(percent!.paragraphSpacingScale, closeTo(1.5, 0.001));
    });

    test('margin 简写同时给出上下两个留白', () {
      expect(
        specFor(
          'p { margin: 0 0 1.4em 0 }',
          '<p>段</p>',
          'p',
        )!.paragraphSpacingScale,
        closeTo(1.4, 0.001),
      );
      expect(
        specFor(
          'p { margin: 0.2em 1em }',
          '<p>段</p>',
          'p',
        )!.paragraphSpacingScale,
        closeTo(0.2, 0.001),
        reason: '两值简写是"纵 横"，下外边距取第一项',
      );

      // 靠上边距分段的书（pgdp 写明"use only top-margin for spacing"）：只取
      // bottom 会把段距折成 0，整章挤在一起。
      final topOnly =
          specFor('p { margin-top: 1em; margin-bottom: 0 }', '<p>段</p>', 'p')!;
      expect(topOnly.paragraphSpacingScale, closeTo(0.0, 0.001));
      expect(topOnly.topMarginScale, closeTo(1.0, 0.001));

      final shorthandTop =
          specFor('p { margin: 1.5em 0 0 0 }', '<p>段</p>', 'p')!;
      expect(shorthandTop.topMarginScale, closeTo(1.5, 0.001));
      expect(
        shorthandTop.paragraphSpacingScale,
        closeTo(0.0, 0.001),
        reason: '四值简写的第三个值是下边',
      );
      expect(
        specFor('p { margin-top: -1em }', '<p>段</p>', 'p')!.topMarginScale,
        closeTo(0.0, 0.001),
        reason: '负留白按 0 收敛，不能倒扣正文',
      );
    });

    test('!important 是作者的强调，去掉标记后照常生效', () {
      final spec = specFor(
        'p { text-indent: 2em !important }',
        '<p>段</p>',
        'p',
      );
      expect(spec!.firstLineIndentChars, 2);
    });

    test('!important 压过特异性更高的普通声明', () {
      // 取胜顺序是 important → 特异性 → 源序。只比特异性的话，书里
      // `p { margin-bottom: 2em !important }` 会被后写的 `.box p { margin-bottom: 0 }` 翻掉。
      expect(
        specFor(
          'p { margin-bottom: 2em !important } .box p { margin-bottom: 0em }',
          '<div class="box"><p>段</p></div>',
          'p',
        )!.paragraphSpacingScale,
        closeTo(2.0, 0.001),
      );

      final bothImportant = specFor(
        'p { margin-bottom: 1em !important } .box p { margin-bottom: 3em !important }',
        '<div class="box"><p>段</p></div>',
        'p',
      );
      expect(
        bothImportant!.paragraphSpacingScale,
        closeTo(3.0, 0.001),
        reason: '两条都强调时仍按特异性定胜负',
      );

      final sameBoth = specFor(
        'p { margin-bottom: 1em !important } p { margin-bottom: 3em !important }',
        '<p>段</p>',
        'p',
      );
      expect(
        sameBoth!.paragraphSpacingScale,
        closeTo(3.0, 0.001),
        reason: '同 important 同特异性，后写的胜出',
      );
    });

    test('html/body 的 % 字号给出像素基准，两级要相乘', () {
      // 先剥结尾字母再解析数字会把 `120%` 整个留在串里，换算失败后 % 分支永远进不去，
      // 基准取不到，后面的 px 就全按 16px 折。
      final percent = specFor(
        'html { font-size: 200% } p { margin-bottom: 32px }',
        '<p>段</p>',
        'p',
      );
      expect(
        percent!.paragraphSpacingScale,
        closeTo(1.0, 0.001),
        reason: '书把基准抬到 32px，32px 的下边距就是 1em',
      );

      final chained = specFor(
        'html { font-size: 200% } body { font-size: 50% } '
            'p { margin-bottom: 16px }',
        '<p>段</p>',
        'p',
      );
      expect(
        chained!.paragraphSpacingScale,
        closeTo(1.0, 0.001),
        reason: '200% 再 50% 组合成 16px；不组合的话 body 会回到 8px，这里算成 2.0',
      );
    });

    test('内联 style 压过样式表', () {
      final spec = specFor(
        'p { text-indent: 2em }',
        '<p style="text-indent: 0em; margin-bottom: 2em">段</p>',
        'p',
      );
      expect(spec!.firstLineIndentChars, 0);
      expect(spec.paragraphSpacingScale, closeTo(2.0, 0.001));
    });

    test('at 规则块整体跳过，其后的规则照常解析', () {
      final spec = specFor(
        '@media (min-width: 600px) { p { text-indent: 4em } } '
            'p { margin-bottom: 1em }',
        '<p>段</p>',
        'p',
      );
      expect(spec!.firstLineIndentChars, isNull);
      expect(spec.paragraphSpacingScale, closeTo(1.0, 0.001));
    });

    test('不支持的选择器放弃整条，不做近似套用', () {
      for (final css in [
        'body > p { text-indent: 2em }',
        'p:first-line { text-indent: 2em }',
        'p[data-x] { text-indent: 2em }',
        '* { text-indent: 2em }',
        'div + p { text-indent: 2em }',
      ]) {
        expect(
          specFor(css, '<div><p>段</p></div>', 'p'),
          isNull,
          reason: '$css 属于未实现的选择器，宁可忽略',
        );
      }
    });

    test('对齐按白名单取值，强制分页不在这一版', () {
      expect(
        specFor('p { text-align: justify }', '<p>段</p>', 'p')!.textAlign,
        TextAlign.justify,
      );
      expect(
        specFor('p { text-align: start }', '<p>段</p>', 'p'),
        isNull,
        reason: '逻辑属性依赖书写方向，本子集不解释',
      );
      expect(
        specFor('h2 { break-before: page }', '<h2>题</h2>', 'h2'),
        isNull,
        reason: '强制分页改的是装页切页时机，没一起实现的能力不进白名单',
      );
    });

    test('缩进量收敛在整字区间内，异常值不外溢', () {
      expect(
        specFor(
          'p { text-indent: none }',
          '<p>段</p>',
          'p',
        )!.firstLineIndentChars,
        0,
      );
      expect(
        specFor(
          'p { text-indent: -2em }',
          '<p>段</p>',
          'p',
        )!.firstLineIndentChars,
        0,
      );
      expect(
        specFor(
          'p { text-indent: 40em }',
          '<p>段</p>',
          'p',
        )!.firstLineIndentChars,
        BookStyleSheet.maxIndentChars,
      );
      expect(
        specFor(
          'p { margin-bottom: 99em }',
          '<p>段</p>',
          'p',
        )!.paragraphSpacingScale,
        BookStyleSheet.maxSpacingScale,
      );
    });

    test('开头的 @charset/@namespace 语句不吃掉后面第一条规则', () {
      // 真实样式表几乎都以这两条语句开头（Standard Ebooks、pgepub 都是）：
      // 它们以分号结尾而不是块，按"跳过块"处理会把紧随其后的第一条真规则一起吞掉。
      final spec = specFor(
        '@charset "utf-8";\n'
            '@namespace epub "http://www.idpf.org/2007/ops";\n'
            'p { text-indent: 1em; margin-bottom: 0 }',
        '<p>段</p>',
        'p',
      );
      expect(spec, isNotNull, reason: '第一条规则被语句型 at-rule 连带跳过');
      expect(spec!.firstLineIndentChars, 1);
      expect(spec.paragraphSpacingScale, 0);
    });

    test('text-align 沿 CSS 继承，缩进与段距不继承', () {
      // 书信与引文的右对齐常见写法是 header { text-align: right }，段落在它里面；
      // margin 与 text-indent 在规范里不继承，父级的值不能落到子上。
      final sheet = BookStyleSheet.parse(
        'header { text-align: right } .letter p { margin-bottom: 0 } '
        'p { text-indent: 1em }',
      );
      final inside = elementWith(
        '<div class="letter"><header><p id="q">抬头</p></header></div>',
        '#q',
      );
      final spec = sheet.styleFor(inside);
      expect(spec?.textAlign, TextAlign.right, reason: '对齐是可继承属性');
      expect(spec?.firstLineIndentChars, 1);
      expect(spec?.paragraphSpacingScale, closeTo(0.0, 0.001));

      final outside = sheet.styleFor(elementWith('<p id="r">正文</p>', '#r'));
      expect(outside?.textAlign, isNull, reason: '不在 header 里就不该继承右对齐');
    });

    test('畸形样式表降级为空而不是抛错', () {
      for (final css in [
        '',
        'p {',
        'p { text-indent',
        '} } { {',
        '/* 没闭合',
        '@media',
      ]) {
        final sheet = BookStyleSheet.parse(css);
        expect(sheet.styleFor(elementWith('<p>段</p>', 'p')), isNull);
      }
    });

    test('规则数量与单表字符都有硬上限', () {
      final many =
          List<String>.generate(
            BookStyleSheet.maxRules + 50,
            (index) => 'c$index { text-indent: 2em }',
          ).join();
      expect(
        BookStyleSheet.parse(many).ruleCount,
        BookStyleSheet.maxRules,
        reason: '畸形样式表不能把规则表撑到无界',
      );

      final oversized = BookStyleSheet.parse(
        '/* ${'x' * BookStyleSheet.maxCssCharacters} */ '
        'p { margin-bottom: 2em }',
      );
      expect(oversized.ruleCount, 0, reason: '超出字符上限的部分整段截断，尾部规则不得生效');

      // 声明计数必须涵盖折算后被丢掉的写法：只在存表时自增的话，一万条 `margin`
      // 就能绕过单条规则的上限。前 100 条给 1em，后面全给 0 —— 计数生效时取到 1em。
      final manyDeclarations = <String>[
        for (var i = 0; i < BookStyleSheet.maxDeclarationsPerRule; i++)
          'margin: 0 0 1em 0',
        for (var i = 0; i < 4000; i++) 'margin: 0',
      ].join(';');
      final capped = specFor('p { $manyDeclarations }', '<p>段</p>', 'p');
      expect(
        capped!.paragraphSpacingScale,
        closeTo(1.0, 0.001),
        reason: '超出上限的声明不该参与折算',
      );
    });
  });

  group('text-indent 沿祖先继承', () {
    // 真书证据：Kindle 导出的三体 style0002.css 只有 `body { text-indent: 2em }`
    // 这一条缩进声明，全章没有一个 p 自己带样式。CSS 2.1 §10.9.1 写的是
    // `text-indent … Inherited: yes`，把它当不可继承属性就是这本书的缩进
    // 在阅读器里根本没有出处，「跟随原书排版」开关两头一样。
    test('整本书的缩进写在 body 上时，段落取到它', () {
      final spec = specFor(
        'body { font-size: 1em; text-align: justify; line-height: 1.618; '
            'text-indent: 2em }',
        '<p>段</p>',
        'p',
      );
      expect(spec, isNotNull, reason: '书的缩进查不到出处');
      expect(spec!.firstLineIndentChars, 2);
      expect(spec.textAlign, TextAlign.justify);
    });

    test('缩进落在包裹层上时也继承进来', () {
      final spec = specFor(
        '.chapter { text-indent: 1em }',
        '<div class="chapter"><p>段</p></div>',
        'p',
      );
      expect(spec?.firstLineIndentChars, 1);
    });

    test('继承只补元素自己没说的那一格，最近的表达者胜出', () {
      const css = 'body { text-indent: 2em } .flat { text-indent: 0em }';
      const body = '<div class="flat"><p id="a">段</p></div><p id="b">段</p>';
      expect(
        specFor(css, body, '#a')?.firstLineIndentChars,
        0,
        reason: '中间那层明写的 0 必须压过更远的 body',
      );
      expect(
        specFor(css, body, '#b')?.firstLineIndentChars,
        2,
        reason: '不在 .flat 里的段落仍继承 body',
      );
      expect(
        specFor(
          'p { text-indent: 1em } .box { text-indent: 0em }',
          '<div class="box"><p>段</p></div>',
          'p',
        )?.firstLineIndentChars,
        1,
        reason: '元素自己说过的值不能被祖先的继承值覆盖',
      );
    });

    test('祖先的内联 style 也参与继承', () {
      final spec = specFor(
        '',
        '<div style="text-indent: 3em"><p>段</p></div>',
        'p',
      );
      expect(spec?.firstLineIndentChars, 3);
    });

    test('margin 不继承：只有 text-indent 与 text-align 走祖先', () {
      final spec = specFor(
        'body { margin-bottom: 3em; text-indent: 1em }',
        '<p>段</p>',
        'p',
      );
      expect(spec?.firstLineIndentChars, 1);
      expect(
        spec?.paragraphSpacingScale,
        isNull,
        reason: '把父级的下边距继承给段落会让整章每一段都多出一份书的留白',
      );
      expect(spec?.topMarginScale, isNull, reason: '上边距同样不继承');
    });
  });

  group('行高折算成相对倍率（T2）', () {
    // 17/17 本实测语料的样式表都写了行距。存的必须是相对基准行高的倍率：
    // 书自己的行高数值不能顶掉读者的行距设置，只能在读者的行距上再乘一份。
    ParagraphStyleSpec? lineHeight(String value) =>
        specFor('p { line-height: $value }', '<p>段</p>', 'p');

    test('纯数字、百分号与 em 折算成同一份倍率', () {
      final base = BookStyleSheet.baseBookLineHeight;
      for (final written in ['1.62', '162%', '1.62em', '1.62rem']) {
        expect(
          lineHeight(written)!.lineHeightScale,
          closeTo(1.62 / base, 0.001),
          reason: '$written 与 1.62 在 CSS 里是同一个行距',
        );
      }
    });

    test('基准行高即阅读器档，折算为 1.0', () {
      expect(
        lineHeight('${BookStyleSheet.baseBookLineHeight}')!.lineHeightScale,
        closeTo(1.0, 0.001),
      );
    });

    test('超出可信区间的值按噪声丢弃，落在区间内的钳到边界', () {
      expect(lineHeight('0.8')?.lineHeightScale, isNull, reason: '窄于 0.9 不是行距');
      expect(
        lineHeight('3.5')?.lineHeightScale,
        isNull,
        reason: '超 3.0 是样式表噪声',
      );
      expect(lineHeight('normal')?.lineHeightScale, isNull);
      // 0.9 与 3.0 在过滤窗口内，但折算后仍要收进"看得出差、又不至于把一页挤成两行"。
      expect(
        lineHeight('0.9')!.lineHeightScale,
        closeTo(BookStyleSheet.minLineHeightScale, 0.001),
      );
      expect(
        lineHeight('3.0')!.lineHeightScale,
        closeTo(BookStyleSheet.maxLineHeightScale, 0.001),
      );
    });

    test('行高只取元素自己那一份，整本书的 body 行距不落到段落上', () {
      // 与 margin 同一族：父级的行距若继承给每一段，读者的行距控件在打开开关后
      // 就再也管不住正文行数。段内明写的行距照常生效。
      expect(
        specFor('body { line-height: 2 }', '<p>段</p>', 'p')?.lineHeightScale,
        isNull,
      );
      expect(
        specFor(
          'body { line-height: 2 } .verse { line-height: 1.2 }',
          '<p class="verse">段</p>',
          '.verse',
        )!.lineHeightScale,
        closeTo(1.2 / BookStyleSheet.baseBookLineHeight, 0.001),
      );
    });

    test('内联 style 的行高压过样式表', () {
      final spec = specFor(
        'p { line-height: 2 }',
        '<p style="line-height: 1.2">段</p>',
        'p',
      );
      expect(
        spec!.lineHeightScale,
        closeTo(1.2 / BookStyleSheet.baseBookLineHeight, 0.001),
      );
    });
  });

  group('段前留白存进 topMarginScale（T3）', () {
    test('margin-top 折算成上留白倍率，与下边距各存一份', () {
      final spec = specFor(
        'p { margin-top: 1.5em; margin-bottom: 0 }',
        '<p>段</p>',
        'p',
      );
      expect(spec!.topMarginScale, closeTo(1.5, 0.001));
      expect(spec.paragraphSpacingScale, 0);
    });

    test('margin 简写的上值同样落到 topMarginScale', () {
      final spec = specFor('p { margin: 2em 0 0 0 }', '<p>段</p>', 'p');
      expect(spec!.topMarginScale, closeTo(2.0, 0.001));
      expect(spec.paragraphSpacingScale, 0);
    });
  });
}
