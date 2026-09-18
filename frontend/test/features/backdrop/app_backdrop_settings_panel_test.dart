import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_preferences.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_api.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_bundled_asset.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_repository.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/presentation/app_backdrop_settings_panel.dart';

void main() {
  testWidgets('移动端背景设置可以启用设备隔离并显示当前配置目标', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    final database = LocalDatabase(NativeDatabase.memory());
    final repository = AppBackdropRepository(database);
    final api = _MockBackdropApi();
    when(() => api.list()).thenAnswer((_) async => []);
    final container = ProviderContainer.test(
      overrides: [
        appBackdropRepositoryProvider.overrideWithValue(repository),
        appBackdropBundledAssetInstallerProvider.overrideWithValue(
          _NoopBundledAssetInstaller(),
        ),
        authSessionProvider.overrideWith(
          () => _MutableSessionNotifier(
            AuthSessionState(
              user: UserProfile(
                id: 'owner-user',
                username: 'owner',
                role: 'MEMBER',
              ),
            ),
          ),
        ),
        appBackdropApiProvider.overrideWithValue(api),
        backdropPreferencesProvider.overrideWith(
          () => _NoopBackdropPreferencesController(repository),
        ),
        appBackdropSelectionTargetProvider.overrideWithValue(
          AppBackdropSelectionTarget.mobile,
        ),
      ],
    );
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      container.dispose();
      await database.close();
    });
    await container.read(appBackdropControllerProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () {
                        unawaited(showAppBackdropSettings(context));
                      },
                      child: const Text('打开背景设置'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开背景设置'));
    await tester.pumpAndSettle();

    final separationSwitch = find.widgetWithText(SwitchListTile, '分别设置桌面与移动端');
    expect(separationSwitch, findsOneWidget);

    await tester.tap(separationSwitch);
    await tester.pumpAndSettle();

    expect(find.text('当前正在设置移动端壁纸'), findsOneWidget);
    final state = container.read(appBackdropControllerProvider).requireValue;
    expect(state.settings.separateDeviceBackdrops, isTrue);
    expect(state.selectionTarget, AppBackdropSelectionTarget.mobile);
  });

  testWidgets('浅色主题下瓦片标题压遮罩恒为白色', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    final database = LocalDatabase(NativeDatabase.memory());
    final repository = AppBackdropRepository(database);
    final api = _MockBackdropApi();
    when(() => api.list()).thenAnswer((_) async => []);
    await repository.upsertServerAssets([
      const BackdropServerAsset(
        id: 'srv-1',
        title: '浅色可读性测试壁纸',
        mediaType: 'image',
        status: 'READY',
        fileSize: 1024,
        contentUrl: 'https://example.com/a.jpg',
        thumbUrl: 'https://example.com/a-thumb.jpg',
      ),
    ]);
    final container = ProviderContainer.test(
      overrides: [
        appBackdropRepositoryProvider.overrideWithValue(repository),
        appBackdropBundledAssetInstallerProvider.overrideWithValue(
          _NoopBundledAssetInstaller(),
        ),
        authSessionProvider.overrideWith(
          () => _MutableSessionNotifier(
            AuthSessionState(
              user: UserProfile(
                id: 'owner-user',
                username: 'owner',
                role: 'MEMBER',
              ),
            ),
          ),
        ),
        appBackdropApiProvider.overrideWithValue(api),
        backdropPreferencesProvider.overrideWith(
          () => _NoopBackdropPreferencesController(repository),
        ),
      ],
    );
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      container.dispose();
      await database.close();
    });
    await container.read(appBackdropControllerProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () {
                        unawaited(showAppBackdropSettings(context));
                      },
                      child: const Text('打开背景设置'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开背景设置'));
    await tester.pumpAndSettle();

    final labelFinder = find.text('浅色可读性测试壁纸');
    expect(labelFinder, findsOneWidget);
    expect(Theme.of(tester.element(labelFinder)).brightness, Brightness.light);
    expect(tester.widget<Text>(labelFinder).style?.color, Colors.white);
  });

  testWidgets('处理中素材在面板打开期间轮询转就绪且视频瓦片有耗时提示', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    final database = LocalDatabase(NativeDatabase.memory());
    final repository = AppBackdropRepository(database);
    final api = _MockBackdropApi();
    var listCalls = 0;
    when(() => api.list()).thenAnswer((_) async {
      listCalls++;
      return [
        BackdropServerAsset(
          id: 'srv-v',
          title: '轮询测试视频',
          mediaType: 'video',
          // 第 1 次=控制器 build,第 2 次=面板打开同步:仍处理中;
          // 第 3 次=轮询 tick:转 READY,验证面板打开期间可自动到达终态。
          status: listCalls >= 3 ? 'READY' : 'PROCESSING',
          fileSize: 2048,
          contentUrl: 'https://example.com/v.mp4',
        ),
      ];
    });
    final container = ProviderContainer.test(
      overrides: [
        appBackdropRepositoryProvider.overrideWithValue(repository),
        appBackdropBundledAssetInstallerProvider.overrideWithValue(
          _NoopBundledAssetInstaller(),
        ),
        authSessionProvider.overrideWith(
          () => _MutableSessionNotifier(
            AuthSessionState(
              user: UserProfile(
                id: 'owner-user',
                username: 'owner',
                role: 'MEMBER',
              ),
            ),
          ),
        ),
        appBackdropApiProvider.overrideWithValue(api),
        backdropPreferencesProvider.overrideWith(
          () => _NoopBackdropPreferencesController(repository),
        ),
      ],
    );
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      container.dispose();
      await database.close();
    });
    await container.read(appBackdropControllerProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () {
                        unawaited(showAppBackdropSettings(context));
                      },
                      child: const Text('打开背景设置'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开背景设置'));
    await tester.pumpAndSettle();

    // 首次同步后仍为处理中:视频瓦片展示耗时提示而非无反馈长等。
    expect(find.text('处理中（视频约需 1-2 分钟）'), findsOneWidget);

    // 3 秒轮询触达服务端,第二次列表返回 READY,瓦片自动转就绪标题。
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(listCalls, greaterThanOrEqualTo(2));
    expect(find.text('轮询测试视频'), findsOneWidget);
    expect(find.text('处理中（视频约需 1-2 分钟）'), findsNothing);
  });
}

class _NoopBundledAssetInstaller extends AppBackdropBundledAssetInstaller {
  @override
  Future<AppBackdropAsset?> install() async => null;
}

class _MutableSessionNotifier extends AuthSessionNotifier {
  _MutableSessionNotifier(this.initialState);

  final AuthSessionState initialState;

  @override
  Future<AuthSessionState> build() async => initialState;
}

class _MockBackdropApi extends Mock implements BackdropApi {}

class _NoopBackdropPreferencesController extends BackdropPreferencesController {
  _NoopBackdropPreferencesController(this._repository);

  final AppBackdropRepository _repository;

  @override
  Future<AppBackdropSettings> build() async {
    return await _repository.loadSettings();
  }

  @override
  Future<void> save(AppBackdropSettings settings) async {
    await _repository.saveSettings(settings);
    state = AsyncData(settings);
  }
}
