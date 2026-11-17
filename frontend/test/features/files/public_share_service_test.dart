import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/files/application/public_share_service.dart';
import 'package:omninest/features/files/domain/public_share.dart';
import 'package:omninest/features/files/presentation/pages/file_share_preview_page.dart';

void main() {
  test('公开分享应用服务转发预览和接受命令', () async {
    final repository = _FakePublicShareRepository();
    final service = PublicShareService(repository);

    await service.preview('share-token', password: 'secret');
    final children = await service.listChildren(
      'share-token',
      parentId: 'folder-1',
    );
    await service.accept(
      'share-token',
      password: 'secret',
      authToken: 'access-token',
    );

    expect(repository.previewCalls, 1);
    expect(repository.acceptCalls, 1);
    expect(repository.lastPassword, 'secret');
    expect(repository.lastAuthToken, 'access-token');
    expect(repository.childrenCalls, 1);
    expect(repository.lastParentId, 'folder-1');
    expect(
      (children as ShareChildrenSuccess).items.map((child) => child.name),
      ['a.txt'],
    );
  });

  testWidgets('分享页面初始预览只请求一次', (tester) async {
    final repository = _FakePublicShareRepository();
    final service = PublicShareService(repository);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [publicShareServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          theme: OmniNestTheme.from(AppThemePalette.dark),
          home: const FileSharePreviewPage(token: 'share-token'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump();

    expect(find.text('shared-file.txt'), findsOneWidget);
    expect(repository.previewCalls, 1);
    expect(tester.takeException(), isNull);
  });
}

class _FakePublicShareRepository implements PublicShareRepository {
  int previewCalls = 0;
  int acceptCalls = 0;
  int accessCalls = 0;
  int childrenCalls = 0;
  String? lastPassword;
  String? lastAuthToken;
  String? lastParentId;

  @override
  Future<ShareChildrenResult> listChildren(
    String token, {
    String? parentId,
    int page = 0,
    int size = 50,
  }) async {
    childrenCalls += 1;
    lastParentId = parentId;
    return const ShareChildrenSuccess(
      items: [
        ShareChild(id: 'c-1', name: 'a.txt', nodeType: 'FILE', sizeBytes: 8),
      ],
      total: 1,
    );
  }

  @override
  Future<SharePreviewResult> preview(String token, {String? password}) async {
    previewCalls += 1;
    lastPassword = password;
    return SharePreviewResult.success(
      fileName: 'shared-file.txt',
      mimeType: 'text/plain',
      sizeBytes: 128,
      resourceType: 'FILE',
      hasPassword: false,
    );
  }

  @override
  Future<ShareAccessResult> access(String token, {String? password}) async {
    accessCalls += 1;
    lastPassword = password;
    return const ShareAccessSuccess('https://signed/shared-file.txt');
  }

  @override
  Future<ShareAcceptResult> accept(
    String token, {
    String? password,
    String? authToken,
    String? targetParentId,
  }) async {
    acceptCalls += 1;
    lastPassword = password;
    lastAuthToken = authToken;
    return ShareAcceptResult.success();
  }
}
