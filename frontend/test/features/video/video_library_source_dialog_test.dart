import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/presentation/widgets/movie_management.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(VideoLibraryType.movie);
  });

  testWidgets('存储位置列表为空时展示提示而不是崩溃', (tester) async {
    await _pumpDialog(tester, const []);

    expect(tester.takeException(), isNull);
    expect(find.text('暂无可用存储位置'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
  });

  testWidgets('仅有不可用存储位置时同样展示提示', (tester) async {
    await _pumpDialog(tester, const [_unhealthyLocation]);

    expect(tester.takeException(), isNull);
    expect(find.text('暂无可用存储位置'), findsOneWidget);
  });

  testWidgets('存在可用存储位置时正常渲染新建表单', (tester) async {
    await _pumpDialog(tester, const [_healthyLocation]);

    expect(tester.takeException(), isNull);
    expect(find.text('添加来源'), findsOneWidget);
    expect(find.textContaining('本地影视盘'), findsOneWidget);
  });

  testWidgets('双权限创建时进入挂载直达模式', (tester) async {
    await _pumpDialog(
      tester,
      const [],
      permissions: _mountDirectPermissions,
      mounts: const [_availableMount],
    );

    expect(find.byType(SegmentedButton<bool>), findsOneWidget);
    expect(find.text('挂载点'), findsOneWidget);
    expect(find.text('存储位置'), findsWidgets);
  });

  testWidgets('仅媒体权限创建时维持位置选择模式', (tester) async {
    await _pumpDialog(
      tester,
      const [_healthyLocation],
      permissions: const {'media:library:manage'},
      mounts: const [_availableMount],
    );

    expect(find.byType(SegmentedButton<bool>), findsNothing);
    expect(find.textContaining('本地影视盘'), findsOneWidget);
  });

  testWidgets('仅媒体权限且无位置时提示不可创建', (tester) async {
    await _pumpDialog(
      tester,
      const [],
      permissions: const {'media:library:manage'},
      mounts: const [_availableMount],
    );

    expect(find.text('暂无可用存储位置'), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
  });

  testWidgets('挂载直达提交携带 mountKey 而非位置 ID', (tester) async {
    final api = _MockMovieApi();
    final submitted = <Symbol, dynamic>{};
    when(
      () => api.createLibrarySource(
        name: any(named: 'name'),
        storageLocationId: any(named: 'storageLocationId'),
        mountKey: any(named: 'mountKey'),
        relativeRoot: any(named: 'relativeRoot'),
        libraryType: any(named: 'libraryType'),
        enabled: any(named: 'enabled'),
      ),
    ).thenAnswer((invocation) async {
      submitted.addAll(invocation.namedArguments);
      return _createdSource;
    });

    await _pumpDialog(
      tester,
      const [],
      api: api,
      permissions: _mountDirectPermissions,
      mounts: const [_availableMount],
    );

    await tester.enterText(find.byType(TextField).first, '挂载直达库');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(submitted[#name], '挂载直达库');
    expect(submitted[#storageLocationId], isNull);
    expect(submitted[#mountKey], 'media');
    expect(submitted[#relativeRoot], '.');
    expect(find.byType(VideoLibrarySourceDialog), findsNothing);
  });
}

const _mountDirectPermissions = {
  'media:library:manage',
  'system:config:read',
  'system:config:manage',
};

const _availableMount = VideoTrustedMount(
  mountKey: 'media',
  displayName: '媒体盘',
  available: true,
);

const _healthyLocation = VideoStorageLocation(
  id: 'loc-1',
  name: '本地影视盘',
  providerType: 'LOCAL_FILESYSTEM',
  mountKey: 'movies',
  relativeRoot: '.',
  scopeType: 'GLOBAL',
  enabled: true,
  healthStatus: 'AVAILABLE',
);

const _unhealthyLocation = VideoStorageLocation(
  id: 'loc-2',
  name: '离线盘',
  providerType: 'LOCAL_FILESYSTEM',
  mountKey: 'archive',
  relativeRoot: '.',
  scopeType: 'GLOBAL',
  enabled: true,
  healthStatus: 'UNAVAILABLE',
);

const _createdSource = VideoLibrarySource(
  id: 'created',
  name: '挂载直达库',
  storageLocationId: 'auto-location',
  relativeRoot: '.',
  libraryType: VideoLibraryType.movie,
  importPolicy: 'MANUAL_REVIEW',
  visibility: MediaLibraryVisibility.private,
  enabled: true,
  scanStatus: 'NEVER_SCANNED',
  healthStatus: 'AVAILABLE',
  lastScannedCount: 0,
  lastCreatedCount: 0,
  lastCandidateCount: 0,
  lastMissingCount: 0,
  version: 0,
);

class _MockMovieApi extends Mock implements MovieApi {}

class _SessionNotifier extends AuthSessionNotifier {
  _SessionNotifier(this.initialState);

  final AuthSessionState initialState;

  @override
  Future<AuthSessionState> build() async => initialState;
}

Future<void> _pumpDialog(
  WidgetTester tester,
  List<VideoStorageLocation> locations, {
  _MockMovieApi? api,
  Set<String>? permissions,
  List<VideoTrustedMount>? mounts,
}) async {
  final effectiveApi = api ?? _MockMovieApi();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        movieApiProvider.overrideWithValue(effectiveApi),
        if (permissions != null)
          authSessionProvider.overrideWith(
            () => _SessionNotifier(
              AuthSessionState(
                user: UserProfile(
                  id: 'admin-id',
                  username: 'admin',
                  role: 'ADMIN',
                  permissions: permissions,
                ),
              ),
            ),
          ),
        if (mounts != null)
          videoTrustedMountsProvider.overrideWith((ref) async => mounts),
      ],
      child: MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Builder(
            builder:
                (context) => Center(
                  child: FilledButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (dialogContext) => VideoLibrarySourceDialog(
                                locations: locations,
                              ),
                        ),
                    child: const Text('open-dialog'),
                  ),
                ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open-dialog'));
  await tester.pumpAndSettle();
}
