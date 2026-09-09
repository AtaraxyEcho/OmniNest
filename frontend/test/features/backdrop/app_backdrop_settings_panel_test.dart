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
