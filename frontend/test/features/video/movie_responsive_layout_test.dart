import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/video/presentation/widgets/movie_responsive_layout.dart';

void main() {
  group('影片封面网格', () {
    test('Android 窄屏保持三列紧凑封面', () {
      final metrics = MoviePosterGridMetrics.resolve(360);

      expect(metrics.columns, 3);
      expect(metrics.compact, isTrue);
    });

    test('大屏手机和平板增加到四列', () {
      final metrics = MoviePosterGridMetrics.resolve(600);

      expect(metrics.columns, 4);
      expect(metrics.compact, isTrue);
    });

    test('桌面端按可用宽度增加列数并限制上限', () {
      final desktop = MoviePosterGridMetrics.resolve(1440);
      final ultraWide = MoviePosterGridMetrics.resolve(3840);

      expect(desktop.columns, greaterThanOrEqualTo(7));
      expect(desktop.compact, isFalse);
      expect(ultraWide.columns, 10);
    });
  });

  group('剧集横向卡片网格', () {
    test('窄屏单列并按桌面宽度逐级扩展', () {
      expect(SeriesLandscapeGridMetrics.resolve(390).columns, 1);
      expect(SeriesLandscapeGridMetrics.resolve(800).columns, 2);
      expect(SeriesLandscapeGridMetrics.resolve(1200).columns, 3);
      expect(SeriesLandscapeGridMetrics.resolve(1600).columns, 4);
      expect(SeriesLandscapeGridMetrics.resolve(2200).columns, 5);
    });
  });
}
