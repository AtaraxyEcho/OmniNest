/// 阅读模块提供给跨 Feature 仪表盘的只读契约，以及桌面书详需要的
/// 批注/书签/统计与控制器入口。
library;

export 'package:omninest/features/reader/application/reader_controller.dart'
    show
        readerCenterControllerProvider,
        readerDashboardProvider,
        readerItemAnnotationsProvider,
        readerItemBookmarksProvider,
        readerItemDetailProvider,
        readerStatsProvider,
        readerStatsOverviewProvider;
// 后端 `ReaderItemDetailDto` 只有 item + progress，章节一律来自文本清单；
// 桌面书详此前只读 detail.chapters，生产环境恒为空。
export 'package:omninest/features/reader/application/reader_book_provider.dart'
    show parsedBookProvider;
export 'package:omninest/features/reader/domain/reader_annotation.dart'
    show ReaderAnnotation;
export 'package:omninest/features/reader/domain/reader_bookmark.dart'
    show ReaderBookmark;
export 'package:omninest/features/reader/domain/reader_models.dart'
    show
        ReaderChapter,
        ReaderDailyReading,
        ReaderDashboard,
        ReaderItem,
        ReaderItemDetail,
        ReaderProgress;
export 'package:omninest/features/reader/domain/reader_stats.dart'
    show ReaderDailyMinutes, ReaderReadingStats, ReaderStatsOverview;
