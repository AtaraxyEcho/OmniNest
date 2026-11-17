import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_content_loader.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_pagination_engine.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  test('分批测高终态与同步全量计算一致', () async {
    final chapters = [ReaderChapter(id: 'chapter-1', title: '第一章')];
    final loader = ReaderContentLoader(allChapters: chapters);
    final settings = ReaderViewSettings();
    // 100 个段落 > 单批 40 块，必然经历多次分批
    final content = ReaderChapterContent(
      title: '第一章',
      content:
          List.generate(
            100,
            (i) => '<p>第 $i 段内容，用于累积测高分批一致性验证。</p><hr/>',
          ).join(),
    );

    final loaded = await loader.loadChapter(
      chapterId: 'chapter-1',
      content: content,
      pageWidth: 320,
      pageHeight: 0,
      settings: settings,
    );
    final data = loaded;
    final initial = List<double>.of(data.cumulativeHeights);
    expect(initial, isNotEmpty);
    expect(data.blocks.length, 200, reason: '段落与分隔线交错避免被合并');

    // 轮询等待分批任务收敛（每批让出一帧）
    var previous = initial;
    for (var turn = 0; turn < 60; turn++) {
      await Future<void>.delayed(Duration.zero);
      if (identical(previous, data.cumulativeHeights) &&
          data.blocks.length + 1 > 0) {
        // 连续两轮引用不变视为收敛
        if (turn > 0) break;
      }
      previous = List<double>.of(data.cumulativeHeights);
    }

    // 终态与同步全量计算逐项一致
    final reference = <double>[];
    var cumulative = 0.0;
    for (final block in data.blocks) {
      cumulative += ReaderPaginationEngine.measureBlockHeight(
        block,
        320,
        settings,
      );
      reference.add(cumulative);
    }
    expect(data.cumulativeHeights.length, reference.length);
    for (var i = 0; i < reference.length; i++) {
      expect(
        (data.cumulativeHeights[i] - reference[i]).abs(),
        lessThan(0.01),
        reason: 'index $i 分批结果应与同步计算一致',
      );
    }
    // 高度单调不减
    for (var i = 1; i < data.cumulativeHeights.length; i++) {
      expect(
        data.cumulativeHeights[i],
        greaterThanOrEqualTo(data.cumulativeHeights[i - 1]),
      );
    }
  });
}
