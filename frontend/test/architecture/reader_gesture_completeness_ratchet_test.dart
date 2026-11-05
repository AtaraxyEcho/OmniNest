import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 阅读器翻页手势完整性闸门。
///
/// 三个条件缺一不可：拖动期间必须监听进度值，否则页面在松手前完全不动；
/// 轻扫必须带真实速度，否则快速短滑会被判回弹；指针取消必须重置状态，
/// 否则系统返回手势或选词抢占后翻页会永久卡在半屏。
void main() {
  String read(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      fail('缺少文件：$path');
    }
    return file.readAsStringSync();
  }

  test('翻页渲染必须同时监听动画控制器与拖动进度', () {
    final source = read(
      'lib/features/reader/presentation/widgets/reader_page_view_render.dart',
    );
    expect(source, contains('Listenable.merge('));
    expect(source, contains('_flipProgressNotifier'));
    expect(source, contains('_isAnimating ? _animController!.value'));
  });

  test('滑动翻页必须跟踪速度并处理指针取消', () {
    final slide = read(
      'lib/features/reader/presentation/widgets/reader_page_view_slide.dart',
    );
    expect(slide, contains('VelocityTracker.withKind'));
    expect(slide, contains('getVelocity()'));
    expect(slide, contains('onPointerCancel: _onPointerCancel'));
    expect(slide, contains('void _onPointerCancel(PointerCancelEvent event)'));
    final custom = read(
      'lib/features/reader/presentation/widgets/reader_page_view_custom.dart',
    );
    expect(custom, contains('onPointerCancel: _onPointerCancel'));
  });

  test('阅读器退出时必须能释放排版静态缓存', () {
    expect(
      read('lib/features/reader/presentation/widgets/block_clipper.dart'),
      contains('static void clearCaches()'),
    );
    expect(
      read(
        'lib/features/reader/presentation/widgets/reader_pagination_text_layout.dart',
      ),
      contains('clearCaches()'),
    );
  });
}
