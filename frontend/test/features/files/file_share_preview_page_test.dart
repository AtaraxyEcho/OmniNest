import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/files/application/public_share_service.dart';
import 'package:omninest/features/files/domain/public_share.dart';
import 'package:omninest/features/files/presentation/pages/file_share_preview_page.dart';

/// 公开分享预览页挂在应用壳层之外：安全区与返回入口必须自带，
/// 否则刘海/横屏切掉卡片，访客直达链接后无路可退。
void main() {
  testWidgets('预览卡片落在 SafeArea 内，顶部返回入口带 tooltip 且达 48dp', (tester) async {
    await tester.pumpWidget(_host(PublicShareService(_OkShareRepository())));
    await tester.pumpAndSettle();

    expect(find.text('report.pdf'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('report.pdf'),
        matching: find.byType(SafeArea),
      ),
      findsWidgets,
      reason: '卡片必须整体落在安全区内',
    );

    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
    );
    expect(
      button.tooltip,
      AppLocalizations.of(
        tester.element(find.byWidget(button)),
      ).coreBackToPortal,
    );
    expect(tester.getSize(find.byWidget(button)), const Size(48, 48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('直达分享链接时返回入口落回门户', (tester) async {
    await tester.pumpWidget(_host(PublicShareService(_OkShareRepository())));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(find.text('portal-root'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('密码态与错误态同样保留 SafeArea 与返回入口', (tester) async {
    await tester.pumpWidget(
      _host(PublicShareService(_PasswordShareRepository())),
    );
    await tester.pumpAndSettle();
    expect(find.text('此分享需要密码访问'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('此分享需要密码访问'),
        matching: find.byType(SafeArea),
      ),
      findsWidgets,
    );
    expect(
      find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _host(PublicShareService(_FailingShareRepository())),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法访问分享链接'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('无法访问分享链接'), matching: find.byType(SafeArea)),
      findsWidgets,
    );
    expect(
      find.widgetWithIcon(IconButton, Icons.arrow_back_rounded),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Widget _host(PublicShareService service) {
  final router = GoRouter(
    initialLocation: '/s/share-1',
    routes: [
      GoRoute(
        path: '/portal',
        builder: (context, state) => const Scaffold(body: Text('portal-root')),
      ),
      GoRoute(
        path: '/s/:token',
        builder:
            (context, state) =>
                FileSharePreviewPage(token: state.pathParameters['token']!),
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [publicShareServiceProvider.overrideWithValue(service)],
    child: MaterialApp.router(
      routerConfig: router,
      theme: OmniNestTheme.from(AppThemePalette.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
    ),
  );
}

class _OkShareRepository implements PublicShareRepository {
  @override
  Future<SharePreviewResult> preview(String token, {String? password}) async {
    return SharePreviewResult.success(
      fileName: 'report.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 2048,
      resourceType: 'FILE',
      hasPassword: false,
    );
  }

  @override
  Future<ShareAcceptResult> accept(
    String token, {
    String? password,
    String? authToken,
  }) async {
    return ShareAcceptResult.success();
  }
}

class _PasswordShareRepository implements PublicShareRepository {
  @override
  Future<SharePreviewResult> preview(String token, {String? password}) async {
    return const SharePreviewNeedPassword('SHARE_NEED_PASSWORD');
  }

  @override
  Future<ShareAcceptResult> accept(
    String token, {
    String? password,
    String? authToken,
  }) async {
    return ShareAcceptResult.error('SHARE_NEED_PASSWORD');
  }
}

class _FailingShareRepository implements PublicShareRepository {
  @override
  Future<SharePreviewResult> preview(String token, {String? password}) async {
    return const SharePreviewError('SHARE_EXPIRED');
  }

  @override
  Future<ShareAcceptResult> accept(
    String token, {
    String? password,
    String? authToken,
  }) async {
    return const ShareAcceptError('SHARE_EXPIRED');
  }
}
