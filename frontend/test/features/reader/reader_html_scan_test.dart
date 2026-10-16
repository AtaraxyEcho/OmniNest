import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/data/reader_content_preprocessor.dart';
import 'package:omninest/features/reader/data/reader_image_cache.dart';
import 'package:omninest/features/reader/data/reader_image_repository_base.dart';
import 'package:omninest/features/reader/domain/reader_html_scan.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_html_text.dart';

/// 定界扫描的行为，以及各调用点在线性时间内的证据。
///
/// 这些调用点原先都用惰性量词正则（`.*?` dotAll、`[^>]*?`、`[^>]*`）：在畸形章节上
/// 每个起点都要扫到串尾。同一份输入的实测对照（`dart` VM 直跑旧实现与新实现）：
/// 400K 个未闭合 `<style ` 前缀 15.5 秒 → 3 毫秒；同样输入的落库预算 9.0 秒 → 2 毫秒
/// （那条调用点随样式表离开正文一起消失，数字留作对照）；
/// 400K 个 `<link ` 前缀 7.4 秒 → 0 毫秒；400K 个 `<img src` 前缀 13.2 秒 → 9 毫秒；
/// 280K 个正文裸尖括号（`a < b` 这类数学散文）82.9 秒 → 53 毫秒。
/// 这些都跑在渲染 isolate 上，等于把阅读器冻住。
///
/// 748 章 CC0 真书正文（9.8M 字符）逐字节对照：剥标签结果、样式表元素定界、
/// `<link rel=stylesheet>` 顺序、`<img>` 占位符改写全部零差异。
void main() {
  group('scanHtmlTags', () {
    test('取属性、标签名与大小写', () {
      const html = '<IMG SRC="a.png" ALT="x" >';
      final tags = scanHtmlTags(html, const {'img'});
      expect(tags, hasLength(1));
      expect(tags.single.name, 'img');
      expect(tags.single.attributeValue('src'), 'a.png');
      expect(tags.single.attributeValue('alt'), 'x');
      expect(tags.single.end, html.length);
    });

    test('标签名后面的第一个字符不是边界时不算这个标签', () {
      expect(scanHtmlTags('<image src="a">', const {'img'}), isEmpty);
      expect(scanHtmlTags('<img src="a">', const {'img'}), hasLength(1));
      expect(scanHtmlTags('<img>', const {'img'}), hasLength(1));
    });

    test('data-src 是另一个属性，不会顶掉 src', () {
      final tags = scanHtmlTags(
        '<img data-src="lazy.png" src="real.png">',
        const {'img'},
      );
      expect(tags.single.attributeValue('data-src'), 'lazy.png');
      expect(tags.single.attributeValue('src'), 'real.png');
    });

    test('同名属性取第一次出现', () {
      final tags = scanHtmlTags('<img src="one.png" src="two.png">', const {
        'img',
      });
      expect(tags.single.attributeValue('src'), 'one.png');
    });

    test('未加引号的值读到闭尖括号为止', () {
      const html = '<img src=a.png><p>x</p>';
      final tags = scanHtmlTags(html, const {'img'});
      final src = tags.single.attribute('src')!;
      expect(src.value, 'a.png');
      expect(html.substring(src.start, src.end), 'src=a.png');
    });

    test('属性值里的引号不参与结束符判定，src 仍能整段替换', () {
      const html = '<img src="a.png" alt="b > c">';
      final tags = scanHtmlTags(html, const {'img'});
      final src = tags.single.attribute('src')!;
      expect(src.value, 'a.png');
      expect(html.substring(src.start, src.end), 'src="a.png"');
      // 引号内的 `>` 不是闭标签：截在这里会让整段属性替换只剩半张标签。
      expect(tags.single.end, html.length);
    });

    test('引号内的尖括号出现在 src 之前时，src 不再丢失', () {
      // E4 之前的口径以第一个 `>` 结束标签：`<img alt="a > b" src="x.png">` 会被
      // 截在 alt 上，图片占位符再也替换不到，章内插图凭空消失。
      const html = '<img alt="a > b" src="x.png"><p>正文</p>';
      final tags = scanHtmlTags(html, const {'img'});
      expect(tags, hasLength(1));
      expect(tags.single.attributeValue('alt'), 'a > b');
      expect(tags.single.attributeValue('src'), 'x.png');
      final src = tags.single.attribute('src')!;
      expect(html.substring(src.start, src.end), 'src="x.png"');
      expect(tags.single.end, html.length - '<p>正文</p>'.length);
    });

    test('单引号同样屏蔽其中的尖括号', () {
      final tags = scanHtmlTags("<img alt='a > b' src='x.png'>", const {'img'});
      expect(tags.single.attributeValue('src'), 'x.png');
    });

    test('整段再没有闭尖括号时后面的标签都无法定界', () {
      expect(scanHtmlTags('<img src="a.png"', const {'img'}), isEmpty);
    });

    test('link 的 rel 与 href 各自独立取值', () {
      final tags = scanHtmlTags(
        '<link href="a.css" REL="Stylesheet">'
        '<link rel="alternate" href="b.xml">'
        '<link href="c.css">',
        const {'link'},
      );
      expect(tags, hasLength(3));
      expect(tags[0].attributeValue('href'), 'a.css');
      expect(tags[0].attributeValue('rel'), 'Stylesheet');
      expect(tags[1].attributeValue('rel'), 'alternate');
      expect(tags[2].attributeValue('rel'), isNull);
    });
  });

  group('scanHtmlElementRanges', () {
    test('区间覆盖开标签到闭标签', () {
      const html = '<style>a{}</style><p>x</p>';
      final ranges = scanHtmlElementRanges(html, const {'style'});
      expect(ranges.single.start, 0);
      expect(
        html.substring(ranges.single.start, ranges.single.end),
        '<style>a{}</style>',
      );
    });

    test('闭标签名后允许空白', () {
      const html = '<style>a{}</style >';
      final ranges = scanHtmlElementRanges(html, const {'style'});
      expect(ranges.single.length, html.length);
    });

    test('未闭合的元素延伸到结尾', () {
      // 浏览器把 RAWTEXT 读到 EOF 时同样不渲染其内容；留在正文里就是朗读念 CSS。
      const html = '<style>p{margin:0}';
      final ranges = scanHtmlElementRanges(html, const {'style'});
      expect(ranges.single.end, html.length);
    });

    test('闭合标签必须是同一个元素名', () {
      const html = '<script>var a=1;</style>x';
      final ranges = scanHtmlElementRanges(html, const {'script'});
      expect(ranges.single.end, html.length);
      expect(scanHtmlElementRanges(html, const {'style'}), isEmpty);
    });

    test('多个元素按序返回且互不重叠', () {
      const html = '<p>1</p><style>a</style><style>b</style><p>2</p>';
      final ranges = scanHtmlElementRanges(html, const {'style'});
      expect(ranges, hasLength(2));
      for (final range in ranges) {
        expect(html.substring(range.start, range.end), startsWith('<style>'));
      }
      expect(ranges.first.end, lessThanOrEqualTo(ranges.last.start));
    });
  });

  group('注释不参与定界（E1）', () {
    test('注释里的 `<style>` 不产出元素区间', () {
      // 手写的 XHTML 里 `<!-- <style> -->` 是常见留痕：按它定界就找不到 `</style>`，
      // 未闭合元素会延伸到串尾，等于把注释之后的整章正文当样式块删空。
      const html = '<p>正文</p><!-- <style>x{y:z} --><p>还是正文</p>';
      expect(scanHtmlElementRanges(html, const {'style'}), isEmpty);
      expect(stripHtml(html), contains('还是正文'));
      expect(stripHtml(html), contains('正文'));
    });

    test('注释里的标签名不参与标签扫描', () {
      const html =
          '<!-- <link rel="stylesheet" href="a.css"> -->'
          '<link rel="stylesheet" href="b.css">';
      final tags = scanHtmlTags(html, const {'link'});
      expect(tags, hasLength(1));
      expect(tags.single.attributeValue('href'), 'b.css');
    });

    test('注释夹在两个真元素之间时两侧照常定界', () {
      const html =
          '<style>a{}</style><!-- <style>x</style> --><style>b{}</style>';
      final ranges = scanHtmlElementRanges(html, const {'style'});
      expect(ranges, hasLength(2));
      expect(
        html.substring(ranges.first.start, ranges.first.end),
        '<style>a{}</style>',
      );
      expect(
        html.substring(ranges.last.start, ranges.last.end),
        '<style>b{}</style>',
      );
    });

    test('注释未闭合时不再往后定界', () {
      // 没有 `-->` 就没有可依赖的边界：注释之后的标签一律不定界，
      // 比把注释里的 `<style>` 当成真元素更保守。
      const html = '<p>正文</p><!-- <style>p{margin:0}';
      expect(scanHtmlElementRanges(html, const {'style'}), isEmpty);
      expect(scanHtmlTags(html, const {'style'}), isEmpty);
      // 注释之前的真标签照常定界，剥标签不会连带把它们吃掉。
      expect(scanHtmlTagRanges(html), hasLength(2));
    });
  });

  group('scanHtmlTagRanges 与 replaceHtmlRanges', () {
    test('裸尖括号后面没有闭尖括号时不当成标签', () {
      expect(scanHtmlTagRanges('a < b'), isEmpty);
      expect(scanHtmlTagRanges('a < b > c'), hasLength(1));
    });

    test('空区间列表原样返回', () {
      expect(replaceHtmlRanges('<p>a</p>', const [], ' '), '<p>a</p>');
    });
  });

  // 按真实耗时判定，不用包级 `timeout:`：同步扫描没有可中断点，超时事件递不进来
  // —— 把实现换回惰性量词正则后，用例仍会在 104 秒后绿。下面每组数字都是同一份
  // 输入在 `dart` VM 上实测的旧实现耗时，阈值 3 秒留了两个数量级的余量。
  group('畸形章节必须在线性时间内扫完', () {
    test('stripHtml：未闭合的 style 前缀吞到结尾，不留 CSS 文本', () {
      final input = _prefixed('<style ', 400000);
      late String result;
      final ms = _elapsedMs(() => result = stripHtml(input));
      // 第一个前缀之前的填充留着，之后的全部按未闭合元素丢掉。
      expect(result, 'x' * 255);
      expect(ms, lessThan(3000), reason: '旧实现同一输入 15484ms，本次 ${ms}ms');
    });

    test('stripHtml：正文里的裸尖括号没有闭尖括号可配', () {
      final input = 'if a < b then ' * 20000;
      late String result;
      final ms = _elapsedMs(() => result = stripHtml(input));
      expect(result, contains('if a < b then'));
      expect(ms, lessThan(3000), reason: '旧实现同一输入 82865ms，本次 ${ms}ms');
    });

    test('样式表定界：整段没有闭尖括号的 `<style ` 前缀', () {
      // 样式表已经不进正文，但 `stripHtml` 仍然要按元素定界剥掉书自己内联的
      // `<style>`，所以这条线性扫描的预算守卫留着。未闭合的元素按规范延伸到
      // 串尾：整段只有一个范围，而不是每个 `<style ` 起点各扫一次。
      final input = _prefixed('<style ', 400000);
      late List<HtmlRange> ranges;
      final ms = _elapsedMs(
        () => ranges = scanHtmlElementRanges(input, const {'style'}),
      );
      expect(ranges, hasLength(1));
      expect(ranges.single.end, input.length);
      expect(ms, lessThan(3000), reason: '旧实现同一输入 8993ms，本次 ${ms}ms');
    });

    test('章节样式表 link 定序', () {
      final input = _prefixed('<link ', 400000);
      late List<HtmlTag> tags;
      final ms = _elapsedMs(() => tags = scanHtmlTags(input, const {'link'}));
      expect(tags, isEmpty);
      expect(ms, lessThan(3000), reason: '旧实现同一输入 7362ms，本次 ${ms}ms');
    });

    test('图片提取：整段没有闭尖括号的 img 前缀', () async {
      ReaderImageCache.init(_DisabledReaderImageRepository());
      final input = '<body>${_prefixed('<img src', 400000)}';
      late ReaderPreprocessedContent result;
      final ms = await _elapsedMsAsync(
        () async =>
            result = await ReaderContentPreprocessor.preprocessForStorage(
              itemId: 'item-scan-budget',
              xhtml: input,
              archive: Archive(),
              contentPath: 'text/chapter.xhtml',
            ),
      );
      expect(result.html, contains('<img src'));
      expect(result.droppedImageCount, 0);
      expect(ms, lessThan(3000), reason: '旧实现同一输入 13153ms，本次 ${ms}ms');
    });
  });
}

int _elapsedMs(void Function() body) {
  final sw = Stopwatch()..start();
  body();
  sw.stop();
  return sw.elapsedMilliseconds;
}

Future<int> _elapsedMsAsync(Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  await body();
  sw.stop();
  return sw.elapsedMilliseconds;
}

/// 每 256 字符一个带边界的标签前缀、整段不给闭尖括号的畸形正文。
String _prefixed(String marker, int length) {
  final buffer = StringBuffer();
  while (buffer.length < length) {
    buffer.write('x' * 255);
    buffer.write(marker);
  }
  return buffer.toString();
}

class _DisabledReaderImageRepository implements ReaderImageRepository {
  @override
  Future<void> saveImage({
    required String itemId,
    required String imagePath,
    required Uint8List bytes,
    String mimeType = 'image/png',
  }) async {}

  @override
  Future<Uint8List?> loadImage({
    required String itemId,
    required String imagePath,
  }) async => null;

  @override
  Future<void> deleteForItem(String itemId) async {}

  @override
  Future<void> cleanOld({int maxAgeDays = 30}) async {}

  @override
  Future<void> clearAll() async {}
}
