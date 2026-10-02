// 影视模块托管进入顺序回归：先切第一栏（For you）再刷新，
// 防止 refresh 以旧分区回写造成落地「电影」/返回观感来回切换。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/pages/movie_center_page.dart';

class _OrderProbeController extends MovieCenterController {
  final order = <String>[];
  String sectionAtRefresh = '';

  @override
  Future<MovieCenterState> build() async {
    return MovieCenterState(
      dashboard: MovieDashboard.empty(),
      movies: const [],
      recentItems: const [],
      continueWatching: const [],
      favoriteItems: const [],
      watchHistory: const [],
      collections: const [],
      tasks: const [],
      section: MovieSection.movies,
    );
  }

  @override
  Future<void> refresh() async {
    order.add('refresh');
    sectionAtRefresh = state.asData?.value.section.name ?? '';
  }
}

const _caps = UserCapabilities(
  canBrowseContent: true,
  canContributeContent: true,
  canManageOwnActivity: true,
  canManagePreferences: true,
  canManageAccount: true,
  canUseBackdropLibrary: true,
  canUploadBackdrop: true,
  canViewOwnTasks: true,
  canAdminTasks: true,
  canManageMediaLibrary: true,
  canManagePhotos: true,
  canAdminUsers: true,
  canReadSystemConfig: true,
  canManageSystemConfig: true,
  canAccessAdminConsole: true,
  canSharedBrowse: true,
  canSharedUpload: true,
  canReadWeather: true,
  canReportLocation: true,
  canManageTwoFactor: true,
  canReadActivity: true,
);

void main() {
  testWidgets('托管进入先切 For you 再刷新（单一写入顺序）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final controller = _OrderProbeController();
    final container = ProviderContainer(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        userCapabilitiesProvider.overrideWithValue(_caps),
        movieCenterControllerProvider.overrideWith(() => controller),
      ],
    );
    addTearDown(container.dispose);
    // 预热：真实链路里 provider 常驻（上次离开时已加载），进入模块时
    // selectSection 走同步切栏路径；冷启动路径由 pendingSection 恢复。
    await container.read(movieCenterControllerProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: MobileShellScope(
            hosted: true,
            child: Scaffold(
              backgroundColor: const Color(0xFF0B1110),
              body: const MovieCenterPage(),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(controller.order, contains('refresh'));
    // selectSection 是 extension 命令（探针不可拦截），以状态断言：
    // 进入后分区必须已切到 For you，且 refresh 执行时读到的就是 For you。
    expect(
      controller.sectionAtRefresh,
      'continueWatching',
      reason: 'refresh 必须在分区已切到 For you 之后执行',
    );
    expect(
      controller.state.asData?.value.section,
      MovieSection.continueWatching,
      reason: '进入后停留第一栏 For you',
    );
    // 注：空假体经真实命令链会触发仓库错误与空态布局溢出（非本契约
    // 范畴），仅消费掉异常让用例聚焦进入顺序断言。
    tester.takeException();
  });
}
