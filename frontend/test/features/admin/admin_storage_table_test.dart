import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_management_models.dart';

/// 带管理权限的可控会话，用于渲染仅对 system:config:manage 可见的新增入口。
class _PermissionedAuthSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async =>
      const AuthSessionState.unauthenticated();

  void signInAsAdmin() {
    state = AsyncData(
      AuthSessionState(
        user: UserProfile(
          id: 'admin-a',
          username: 'admin-a',
          role: 'SUPER_ADMIN',
          roles: const {'SUPER_ADMIN'},
          permissions: const {'system:config:manage', 'media:library:manage'},
        ),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
  }

  @override
  Future<bool> refreshSession() async => true;
}

void main() {
  testWidgets('存储管理页表格渲染且行点击打开详情弹窗', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const location = AdminStorageLocation(
      id: 'loc-1',
      name: '影视主库',
      providerType: 'LOCAL',
      managementMode: 'MANAGED',
      mountKey: 'media-01',
      relativeRoot: '/media/movies',
      scopeType: 'SHARED',
      enabled: true,
      healthStatus: 'AVAILABLE',
      nodeId: 'node-01',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoStorageLocationsProvider.overrideWith(
            (ref) async => const <VideoStorageLocation>[],
          ),
          videoLibrarySourcesProvider.overrideWith(
            (ref) async => const <VideoLibrarySource>[],
          ),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: AdminStoragePage(
                view: AdminStorageManagementView(
                  buckets: [],
                  locations: [location],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 表格渲染：列头与行数据齐备，健康 AVAILABLE 为"可用"。
    expect(find.text('影视主库'), findsOneWidget);
    expect(find.text('media-01'), findsOneWidget);
    expect(find.text('可用'), findsOneWidget);

    // 行点击打开详情弹窗（弹窗内再次出现挂载键字段）。
    await tester.tap(find.text('media-01'));
    await tester.pumpAndSettle();
    expect(find.textContaining('media-01'), findsNWidgets(2));
    expect(find.textContaining('MANAGED'), findsOneWidget);
  });

  testWidgets('库源行点击打开父子嵌套管理窗口', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const source = VideoLibrarySource(
      id: 'src-1',
      name: '电影收藏',
      storageLocationId: 'loc-1',
      relativeRoot: 'Movie',
      libraryType: VideoLibraryType.movie,
      importPolicy: 'MANUAL_REVIEW',
      visibility: MediaLibraryVisibility.private,
      enabled: true,
      scanStatus: 'READY',
      healthStatus: 'AVAILABLE',
      lastScannedCount: 24,
      lastCreatedCount: 0,
      lastCandidateCount: 3,
      lastMissingCount: 0,
      version: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoStorageLocationsProvider.overrideWith(
            (ref) async => const <VideoStorageLocation>[
              VideoStorageLocation(
                id: 'loc-1',
                name: '影视主库',
                providerType: 'LOCAL',
                mountKey: 'media-01',
                relativeRoot: 'Movie',
                scopeType: 'SHARED',
                enabled: true,
                healthStatus: 'AVAILABLE',
              ),
            ],
          ),
          videoLibrarySourcesProvider.overrideWith(
            (ref) async => const <VideoLibrarySource>[source],
          ),
          latestMediaScanRunProvider(
            'src-1',
          ).overrideWith((ref) => Stream.value(null)),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: AdminStoragePage(
                view: AdminStorageManagementView(buckets: [], locations: []),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 行点击打开管理窗口：父子嵌套父区默认展开，标题带库源名。
    await tester.tap(find.text('电影收藏'));
    await tester.pumpAndSettle();
    expect(find.text('库源信息'), findsOneWidget);
    expect(find.text('发现与审阅'), findsOneWidget);
    expect(find.textContaining('媒体库管理'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('挂载位置向导弹窗按内容自适应高度', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(
            _PermissionedAuthSessionNotifier.new,
          ),
          videoStorageLocationsProvider.overrideWith(
            (ref) async => const <VideoStorageLocation>[],
          ),
          videoLibrarySourcesProvider.overrideWith(
            (ref) async => const <VideoLibrarySource>[],
          ),
          adminMountDirectoriesProvider.overrideWith(
            (ref, key) async => const <AdminStorageDirectory>[],
          ),
        ],
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: AdminStoragePage(
                view: AdminStorageManagementView(
                  buckets: [],
                  locations: [],
                  trustedMounts: [
                    AdminTrustedMount(
                      mountKey: 'media-01',
                      displayName: 'media-01',
                      available: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdminStoragePage)),
    );
    (container.read(authSessionProvider.notifier)
            as _PermissionedAuthSessionNotifier)
        .signInAsAdmin();
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加挂载位置'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // AlertDialog 默认垂直内边距 24×2；目录浏览区若用 Expanded 会把弹窗
    // 卡片撑满可用高度（1200 - 48 = 1152），限高后应明显小于可用高度。
    // AlertDialog 元素命中的是外层 padding 壳，可见卡片是其内部的 Material。
    final cardFinder =
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Material),
            )
            .first;
    final dialogHeight = tester.getSize(cardFinder).height;
    expect(dialogHeight, lessThan(1152));
    expect(dialogHeight, greaterThan(400));
  });
}
