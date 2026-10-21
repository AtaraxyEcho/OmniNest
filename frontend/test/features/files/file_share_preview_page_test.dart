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

  testWidgets('文件夹分享列出子项，点进子目录后可返回上一级', (tester) async {
    await tester.pumpWidget(
      _host(PublicShareService(_FolderShareRepository())),
    );
    await tester.pumpAndSettle();

    expect(find.text('共 2 项'), findsOneWidget);
    expect(find.text('videos'), findsOneWidget);
    expect(find.text('a.mkv'), findsOneWidget);
    expect(find.text('保存到我的文件'), findsOneWidget);

    await tester.tap(find.text('videos'));
    await tester.pumpAndSettle();

    expect(find.text('b.mkv'), findsOneWidget);
    expect(find.text('a.mkv'), findsNothing);
    expect(find.text('共 1 项'), findsOneWidget);

    await tester.tap(
      find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded),
    );
    await tester.pumpAndSettle();

    expect(find.text('a.mkv'), findsOneWidget);
    expect(find.text('videos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /// 没有系统账号的外部访客必须能直接拿到文件：只有「保存到我的文件」时，
  /// 点下去会被送去登录页，分享链接对访客等于无效。
  testWidgets('单文件分享为访客保留免登录直接下载入口', (tester) async {
    final repository = _OkShareRepository();
    await tester.pumpWidget(_host(PublicShareService(repository)));
    await tester.pumpAndSettle();

    expect(find.text('下载'), findsOneWidget);

    await tester.tap(
      find.widgetWithIcon(OutlinedButton, Icons.download_rounded),
    );
    await tester.pumpAndSettle();

    expect(repository.accessCalls, 1);
    expect(tester.takeException(), isNull);
  });

  /// 输错提取码后界面原样不动，访客无从判断是「要密码」还是「密码错了」。
  testWidgets('提取码被拒时在输入框下方显示服务端提示', (tester) async {
    await tester.pumpWidget(
      _host(PublicShareService(_WrongPasswordShareRepository())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'bad-code');
    await tester.tap(find.text('访问'));
    await tester.pumpAndSettle();

    expect(find.text('提取码不正确'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /// 服务端只放行一页 50 条，第 51 条之后访客原本既看不到也下载不了。
  testWidgets('文件夹分享子项触底后续页', (tester) async {
    final repository = _PagedShareRepository();
    await tester.pumpWidget(_host(PublicShareService(repository)));
    await tester.pumpAndSettle();

    expect(repository.requestedPages.first, 0);
    // 长列表按虚拟化只构建可见行，断言取可见项与请求页码，不数不可见的尾项。
    expect(find.text('child-0'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(repository.requestedPages, contains(1));

    await tester.scrollUntilVisible(find.text('tail-31'), 200);
    expect(find.text('tail-31'), findsOneWidget);
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
  int accessCalls = 0;

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
  Future<ShareChildrenResult> listChildren(
    String token, {
    String? parentId,
    int page = 0,
    int size = 50,
  }) async {
    return const ShareChildrenSuccess(items: [], total: 0);
  }

  @override
  Future<ShareAccessResult> access(String token, {String? password}) async {
    accessCalls += 1;
    return const ShareAccessSuccess('https://signed/report.pdf');
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

/// 文件夹分享：根目录两项，进入子目录后只剩一项。
class _FolderShareRepository implements PublicShareRepository {
  @override
  Future<SharePreviewResult> preview(String token, {String? password}) async {
    return const SharePreviewSuccess(
      fileName: 'trip',
      sizeBytes: 0,
      resourceType: 'FOLDER',
      hasPassword: false,
    );
  }

  @override
  Future<ShareChildrenResult> listChildren(
    String token, {
    String? parentId,
    int page = 0,
    int size = 50,
  }) async {
    if (parentId == null) {
      return const ShareChildrenSuccess(
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
        total: 2,
      );
    }
    return const ShareChildrenSuccess(
      items: [
        ShareChild(
          id: 'b-1',
          name: 'b.mkv',
          nodeType: 'FILE',
          sizeBytes: 2048,
          downloadUrl: 'https://signed/b.mkv',
        ),
      ],
      total: 1,
    );
  }

  @override
  Future<ShareAccessResult> access(String token, {String? password}) async {
    return const ShareAccessFailure('SHARE_NEED_PASSWORD');
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
  Future<ShareChildrenResult> listChildren(
    String token, {
    String? parentId,
    int page = 0,
    int size = 50,
  }) async {
    return const ShareChildrenFailure('SHARE_NEED_PASSWORD');
  }

  @override
  Future<ShareAccessResult> access(String token, {String? password}) async {
    return const ShareAccessFailure('SHARE_NEED_PASSWORD');
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
  Future<ShareChildrenResult> listChildren(
    String token, {
    String? parentId,
    int page = 0,
    int size = 50,
  }) async {
    return const ShareChildrenFailure('SHARE_EXPIRED');
  }

  @override
  Future<ShareAccessResult> access(String token, {String? password}) async {
    return const ShareAccessFailure('SHARE_EXPIRED');
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

/// 已提交提取码仍被服务端拒绝。
class _WrongPasswordShareRepository implements PublicShareRepository {
  @override
  Future<SharePreviewResult> preview(String token, {String? password}) async {
    return const SharePreviewNeedPassword('提取码不正确');
  }

  @override
  Future<ShareChildrenResult> listChildren(
    String token, {
    String? parentId,
    int page = 0,
    int size = 50,
  }) async {
    return const ShareChildrenFailure('提取码不正确');
  }

  @override
  Future<ShareAccessResult> access(String token, {String? password}) async {
    return const ShareAccessFailure('提取码不正确');
  }

  @override
  Future<ShareAcceptResult> accept(
    String token, {
    String? password,
    String? authToken,
  }) async {
    return const ShareAcceptError('提取码不正确');
  }
}

/// 子项超过一页：首页 30 条，续页再给 2 条。
class _PagedShareRepository implements PublicShareRepository {
  final List<int> requestedPages = <int>[];

  @override
  Future<SharePreviewResult> preview(String token, {String? password}) async {
    return const SharePreviewSuccess(
      fileName: 'bundle',
      sizeBytes: 0,
      resourceType: 'FOLDER',
      hasPassword: false,
    );
  }

  @override
  Future<ShareChildrenResult> listChildren(
    String token, {
    String? parentId,
    int page = 0,
    int size = 50,
  }) async {
    requestedPages.add(page);
    final items =
        page == 0
            ? List.generate(
              30,
              (index) => ShareChild(
                id: 'id-$index',
                name: 'child-$index',
                nodeType: 'FILE',
                sizeBytes: 8,
              ),
            )
            : const [
              ShareChild(
                id: 'id-30',
                name: 'child-30',
                nodeType: 'FILE',
                sizeBytes: 8,
              ),
              ShareChild(
                id: 'id-31',
                name: 'tail-31',
                nodeType: 'FILE',
                sizeBytes: 8,
              ),
            ];
    return ShareChildrenSuccess(items: items, total: 32);
  }

  @override
  Future<ShareAccessResult> access(String token, {String? password}) async {
    return const ShareAccessFailure('SHARE_NEED_PASSWORD');
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
