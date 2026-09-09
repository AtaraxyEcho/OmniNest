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
    if (remote == settings) {
      return settings;
    }
    // 本地已启用且选中一致:以本地为准并回写,避免远端陈旧 enabled=false
    // 把刚注册的默认壁纸打回未启用(首次登录/启动无背景的主因)。
    if (settings.enabled &&
        !remote.enabled &&
        _sameSelection(settings, remote)) {
      await service.patch(
        userId: userId,
        scope: backdropPreferenceScope,
        changes: AppBackdropSettingsJson.toChanges(settings),
      );
      return settings;
    }
    if (_hasUsableSelection(remote)) {
      await ref.read(appBackdropRepositoryProvider).saveSettings(remote);
      return remote;
    }
    if (!_hasUsableSelection(settings)) {
      await ref.read(appBackdropRepositoryProvider).saveSettings(remote);
      return remote;
    }
    return settings;
  }

  bool _sameSelection(AppBackdropSettings a, AppBackdropSettings b) {
    return a.selectedBackdropId == b.selectedBackdropId &&
        a.desktopBackdropId == b.desktopBackdropId &&
        a.mobileBackdropId == b.mobileBackdropId;
  }

  bool _hasUsableSelection(AppBackdropSettings settings) {
    return settings.selectedBackdropId != null ||
        settings.desktopBackdropId != null ||
        settings.mobileBackdropId != null;
  }

  /// 保存设置:先写本地镜像保证即时生效,再同步服务端。
  /// 冲突时按最新版本重放用户意图;远端收敛结果不会回退 enabled/选中。
  Future<void> save(AppBackdropSettings settings) async {
    await ref.read(appBackdropRepositoryProvider).saveSettings(settings);
    state = AsyncData(settings);
    final userId = _userId;
    if (userId == null) {
      return;
    }
    final service = ref.read(preferenceSyncServiceProvider);
    try {
      final snapshot = await service.patch(
        userId: userId,
        scope: backdropPreferenceScope,
        changes: AppBackdropSettingsJson.toChanges(settings),
      );
      final remote = AppBackdropSettingsJson.fromPreferences(
        snapshot.preferences,
        settings,
      );
      if (remote != settings && _remoteWins(settings, remote)) {
        await ref.read(appBackdropRepositoryProvider).saveSettings(remote);
        state = AsyncData(remote);
        return;
      }
      if (remote != settings) {
        // 服务端仍与本次操作不一致时,再写一次用户意图,避免选中/启用丢失。
        final retried = await service.patch(
          userId: userId,
          scope: backdropPreferenceScope,
          changes: AppBackdropSettingsJson.toChanges(settings),
        );
        final finalRemote = AppBackdropSettingsJson.fromPreferences(
          retried.preferences,
          settings,
        );
        if (_remoteWins(settings, finalRemote)) {
          await ref
              .read(appBackdropRepositoryProvider)
              .saveSettings(finalRemote);
          state = AsyncData(finalRemote);
          return;
        }
      }
    } on Exception {
      // 保留本地用户意图,由 pending 与下次同步收敛。
    }
  }

  /// 仅当远端同时保留可用选中且未把“已启用”打回关闭时,才用远端覆盖本地。
  bool _remoteWins(AppBackdropSettings intended, AppBackdropSettings remote) {
    if (intended.enabled && !remote.enabled) {
      return false;
    }
    final intendedId = intended.selectedBackdropId;
    if (intendedId != null &&
        intendedId.isNotEmpty &&
        remote.selectedBackdropId != intendedId &&
        remote.desktopBackdropId != intendedId &&
        remote.mobileBackdropId != intendedId) {
      return false;
    }
    return remote != intended;
  }
}
