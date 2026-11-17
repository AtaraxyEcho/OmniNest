import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/reader/presentation/pages/reader_view_page.dart';

/// 阅读页章节来源的降级次序。
///
/// 后端详情响应不带章节，`ReaderItemDetail.chapters` 恒为空；只看它时底栏的
/// "第 N / M 章" 整块消失、章末卡的位次解析不到，所以清单必须来自已装载章节或
/// 服务端清单，并且在前一级为空时继续降级。
void main() {
  final loaded = <ReaderChapter>[
    ReaderChapter(id: 'chapter_0', title: 'loaded 1'),
  ];
  final manifest = <ReaderChapter>[
    ReaderChapter(id: 'chapter_0', title: 'manifest 1'),
    ReaderChapter(id: 'chapter_1', title: 'manifest 2'),
  ];

  test('已装载章节优先于服务端清单', () {
    expect(
      readerChapterSource(
        loaded: loaded,
        manifest: manifest,
        fromDetail: const [],
      ),
      same(loaded),
    );
  });

  test('未装载时降级到清单，两者都空时降级到详情响应', () {
    expect(
      readerChapterSource(
        loaded: const [],
        manifest: manifest,
        fromDetail: loaded,
      ),
      same(manifest),
    );
    expect(
      readerChapterSource(loaded: null, manifest: null, fromDetail: loaded),
      same(loaded),
    );
  });

  test('三级全空返回空列表而不是 null', () {
    expect(
      readerChapterSource(loaded: null, manifest: [], fromDetail: const []),
      isEmpty,
    );
  });
}
