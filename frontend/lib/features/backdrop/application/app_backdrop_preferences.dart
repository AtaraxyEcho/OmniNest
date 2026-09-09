import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_settings_json.dart';

const backdropPreferenceScope = 'backdrop';

final backdropPreferencesProvider =
    AsyncNotifierProvider<BackdropPreferencesController, AppBackdropSettings>(
      BackdropPreferencesController.new,
    );

/// 背景设置偏好控制器。
///
/// 服务端用户偏好(scope=backdrop)为事实来源;drift 设置行作为渲染用的离线镜像。
/// 未登录时退化为纯本地设置,不参与同步。
class BackdropPreferencesController extends AsyncNotifier<AppBackdropSettings> {
  String? _userId;

  @override
  Future<AppBackdropSettings> build() async {
    final session = await ref.watch(authSessionProvider.future);
    _userId = session.user?.id;
    var settings = await ref.read(appBackdropRepositoryProvider).loadSettings();
    final userId = _userId;
    if (userId == null) {
      return settings;
    }
    final service = ref.read(preferenceSyncServiceProvider);
    var snapshot = await service.load(
      userId: userId,
      scope: backdropPreferenceScope,
    );
    if (snapshot.preferences.isEmpty) {
      // 首次上云:把本地已保存的设置作为初始值写入服务端。
      snapshot = await service.patch(
        userId: userId,
        scope: backdropPreferenceScope,
        changes: AppBackdropSettingsJson.toChanges(settings),
      );
    }
    final remote = AppBackdropSettingsJson.fromPreferences(
      snapshot.preferences,
      settings,
    );
    if (remote != settings) {
      await ref.read(appBackdropRepositoryProvider).saveSettings(remote);
      settings = remote;
    }
    return settings;
  }

  /// 保存设置:先写本地镜像保证即时生效,再同步服务端并按服务端结果收敛。
  Future<void> save(AppBackdropSettings settings) async {
    await ref.read(appBackdropRepositoryProvider).saveSettings(settings);
    state = AsyncData(settings);
    final userId = _userId;
    if (userId == null) {
      return;
    }
    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .patch(
          userId: userId,
          scope: backdropPreferenceScope,
          changes: AppBackdropSettingsJson.toChanges(settings),
        );
    final remote = AppBackdropSettingsJson.fromPreferences(
      snapshot.preferences,
      settings,
    );
    if (remote != settings) {
      await ref.read(appBackdropRepositoryProvider).saveSettings(remote);
      state = AsyncData(remote);
    }
  }
}
