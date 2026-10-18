import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/files/data/file_providers.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_repository.dart';
import 'package:omninest/features/files/domain/public_share.dart';
import 'package:omninest/features/files/presentation/widgets/shared_folder_browser.dart';

/// 定向分享的接收人没有分享 token，只能按分享标识浏览；这里钉住
/// "根目录 → 子目录 → 返回"的调用参数与列表内容，防止退回点开即报错的旧行为。
void main() {
  testWidgets('定向分享文件夹可逐级进入并返回上一级', (tester) async {
    final repository = _BrowseFakeRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fileRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const Scaffold(body: SharedFolderBrowser(shareId: 'share-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.requestedParentIds, [null]);
    expect(find.text('a.mkv'), findsOneWidget);
    expect(find.text('videos'), findsOneWidget);
    expect(find.text('共 2 项'), findsOneWidget);

    await tester.tap(find.text('videos'));
    await tester.pumpAndSettle();

    expect(repository.requestedParentIds, [null, 'f-1']);
    expect(find.text('b.mkv'), findsOneWidget);
    expect(find.text('a.mkv'), findsNothing);
    expect(find.text('共 1 项'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(repository.requestedParentIds, [null, 'f-1', null]);
    expect(find.text('a.mkv'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('加载失败时给出重试入口而不是空白', (tester) async {
    final repository = _FailingBrowseRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fileRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const Scaffold(body: SharedFolderBrowser(shareId: 'share-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, '重试'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '重试'));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    expect(tester.takeException(), isNull);
  });
}

class _BrowseFakeRepository implements FileRepository {
  final requestedParentIds = <String?>[];

  @override
  Future<FilesSubPage<ShareChild>> listSharedFolderChildren({
    required String shareId,
    String? parentId,
    int page = 0,
    int size = 50,
  }) async {
    requestedParentIds.add(parentId);
    if (parentId == null) {
      return const FilesSubPage(
        items: [
          ShareChild(
            id: 'f-1',
            name: 'videos',
            nodeType: 'FOLDER',
            sizeBytes: 0,
          ),
          ShareChild(
            id: 'a-1',
            name: 'a.mkv',
            nodeType: 'FILE',
            sizeBytes: 1024,
            downloadUrl: 'https://signed/a.mkv',
          ),
        ],
        page: 0,
        size: 50,
        totalElements: 2,
        totalPages: 1,
      );
    }
    return const FilesSubPage(
      items: [
        ShareChild(
          id: 'b-1',
          name: 'b.mkv',
          nodeType: 'FILE',
          sizeBytes: 2048,
          downloadUrl: 'https://signed/b.mkv',
        ),
      ],
      page: 0,
      size: 50,
      totalElements: 1,
      totalPages: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingBrowseRepository implements FileRepository {
  int calls = 0;

  @override
  Future<FilesSubPage<ShareChild>> listSharedFolderChildren({
    required String shareId,
    String? parentId,
    int page = 0,
    int size = 50,
  }) async {
    calls += 1;
    throw StateError('SHARE_EXPIRED');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
