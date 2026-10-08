import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations_en.dart';
import 'package:omninest/app/l10n/app_localizations_zh.dart';
import 'package:omninest/features/reader/application/reader_chapter_load_coordinator.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';

/// 摘要：钉住章节失败原因到用户文案的映射。
///
/// 兜底链的失败原因决定用户下一步动作（联网、重新解析、或只能重试），
/// 未标注原因时必须回到通用文案，不能把本地解析超限之类的错误说成"需要联网"。
void main() {
  test('每种失败原因各自映射到对应文案（中英）', () {
    final en = AppLocalizationsEn();
    final zh = AppLocalizationsZh();

    expect(
      chapterLoadErrorMessage(en, ReaderChapterFailure.needsNetwork),
      en.readerChapterNeedsNetwork,
    );
    expect(
      chapterLoadErrorMessage(en, ReaderChapterFailure.needsReparse),
      en.readerChapterNeedsReparse,
    );
    expect(chapterLoadErrorMessage(en, null), en.readerChapterLoadFailed);
    expect(
      chapterLoadErrorMessage(zh, ReaderChapterFailure.needsNetwork),
      isNot(en.readerChapterLoadFailed),
    );
    expect(chapterLoadErrorMessage(zh, null), zh.readerChapterLoadFailed);
    // 编码不支持是可动作的失败（转 UTF-8 重导），不能退化成通用"加载失败"。
    expect(
      chapterLoadErrorMessage(en, ReaderChapterFailure.unsupportedEncoding),
      en.readerChapterUnsupportedEncoding,
    );
    expect(
      chapterLoadErrorMessage(zh, ReaderChapterFailure.unsupportedEncoding),
      zh.readerChapterUnsupportedEncoding,
    );
    expect(
      zh.readerChapterUnsupportedEncoding,
      isNot(zh.readerChapterLoadFailed),
    );
  });
}
