// 桌面影视搜索框限长回归：框里的文本必须等于真正打给服务端的关键词。
// 服务端影视库关键词限 200 字，超长输入会变成一次被拒的请求，而不是"搜不到"。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/presentation/pages/movie_center_page.dart';

class _StubCenterController extends MovieCenterController {
  /// 防抖后真正打给服务端的那次关键词（`setSearchQuery` 是扩展方法，不能覆写拦截）。
  String? keywordAtRefresh;

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
    keywordAtRefresh = state.asData?.value.searchQuery;
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
  testWidgets('桌面影视搜索框把关键词限在服务端上限内', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = _StubCenterController();
    final container = ProviderContainer(
      overrides: [
        authSessionStoreProvider.overrideWithValue(MemoryAuthSessionStore()),
        userCapabilitiesProvider.overrideWithValue(_caps),
        movieCenterControllerProvider.overrideWith(() => controller),
      ],
    );
    addTearDown(container.dispose);
    await container.read(movieCenterControllerProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: MovieCenterPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final field = find.byType(TextField);
    expect(field, findsWidgets, reason: '桌面工作台头部应渲染影视搜索框');

    await tester.enterText(
      field.first,
      'a' * (ScopedSearchLimits.maxQueryLength + 51),
    );
    await tester.pump();

    // 输入侧就截断：框里的字数与防抖后真正打出去的关键词长度都必须是上限。
    // 该 TextField 未传 controller，读它渲染出来的 EditableText。
    final editable = tester.widget<EditableText>(
      find.descendant(of: field.first, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text.length, ScopedSearchLimits.maxQueryLength);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      controller.keywordAtRefresh?.length,
      ScopedSearchLimits.maxQueryLength,
    );
  });
}
