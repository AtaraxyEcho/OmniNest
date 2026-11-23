import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/preferences/preference_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用字体档位。跟随系统不覆盖环境 TextScaler，其余档位以线性倍率
/// 与系统缩放组合应用。
enum FontScalePreset {
  followSystem(null),
  scale85(0.85),
  compact(0.9),
  scale95(0.95),
  standard(1.0),
  scale105(1.05),
  scale110(1.1),
  comfortable(1.15),
  scale120(1.2),
  large(1.25);

  const FontScalePreset(this.scale);

  final double? scale;

  int? get percent => scale == null ? null : (scale! * 100).round();

  static FontScalePreset fromPercent(int percent) {
    return FontScalePreset.values.firstWhere(
      (preset) => preset.percent == percent,
      orElse: () => FontScalePreset.standard,
    );
  }

  static FontScalePreset fromName(String? name) {
    for (final preset in FontScalePreset.values) {
      if (preset.name == name) {
        return preset;
      }
    }
    return FontScalePreset.followSystem;
  }
}

final fontScaleControllerProvider =
    NotifierProvider<FontScaleController, FontScalePreset>(
      FontScaleController.new,
    );

/// 应用字体档位状态控制器。
///
/// 与 [AppearanceController] 同写 `appearance.v1` 作用域的 `fontScale`
/// 键：设备本地预读避免首帧跳档，登录后由远端快照覆盖，未登录回退
/// 设备值。档位变更即时生效于根部 ComposedScaler。
class FontScaleController extends Notifier<FontScalePreset> {
  String? _activeUserId;

  /// 上一次绑定的非空账号：用于识别"换号"，避免把上一账号的设备偏好回写到新账号云端。
  String? _lastBoundUserId;
  int _loadGeneration = 0;

  @override
  FontScalePreset build() {
    final initial = FontScalePreset.fromName(
      ref.read(appBootstrapDataProvider).fontScaleName,
    );
    try {
      ref.listen(authSessionProvider, (_, next) {
        final userId = next.value?.user?.id;
        unawaited(_bindUser(userId));
      }, fireImmediately: true);
    } on Object {
      // 测试或离线环境未注入认证会话时静默回退本地偏好。
    }
    return initial;
  }

  Future<void> setPreset(FontScalePreset preset) async {
    if (!ref.mounted) {
      return;
    }
    state = preset;
    await _writeDevicePreset(preset);
    if (!ref.mounted) {
      return;
    }
    final userId = _activeUserId;
    final service = _tryReadSyncService();
    if (userId == null || service == null) {
      return;
    }
    try {
      await service.patch(
        userId: userId,
        scope: appearancePreferenceScope,
        changes: {'schemaVersion': 1, 'fontScale': preset.name},
      );
    } on Object {
      // 离线或远端不可用时静默保留本地偏好，待下次同步收敛。
    }
  }

  /// 从远端重新同步字体档位，并保留本地待提交变更。
  Future<void> refreshFromRemote() async {
    if (!ref.mounted) {
      return;
    }
    final userId = _activeUserId;
    final service = _tryReadSyncService();
    if (userId == null || service == null) return;
    try {
      final snapshot = await service.synchronize(
        userId: userId,
        scope: appearancePreferenceScope,
      );
      if (!ref.mounted || _activeUserId != userId) return;
      final remoteName = snapshot.preferences['fontScale']?.toString();
      if (remoteName == null || remoteName.isEmpty) return;
      final resolved = FontScalePreset.fromName(remoteName);
      state = resolved;
      await _writeDevicePreset(resolved);
    } on Object {
      // 离线或远端不可用时静默保留本地偏好。
    }
  }

  Future<void> _bindUser(String? userId) async {
    if (!ref.mounted) {
      return;
    }
    final previousUserId = _lastBoundUserId;
    _activeUserId = userId;
    final generation = ++_loadGeneration;
    if (userId == null) {
      final preferences = await SharedPreferences.getInstance();
      if (!ref.mounted) {
        return;
      }
      if (generation == _loadGeneration) {
        state = FontScalePreset.fromName(
          preferences.getString(appearanceDeviceFontScaleKey),
        );
      }
      return;
    }

    final service = _tryReadSyncService();
    if (service == null) {
      return;
    }
    try {
      final snapshot = await service.load(
        userId: userId,
        scope: appearancePreferenceScope,
      );
      if (!ref.mounted ||
          generation != _loadGeneration ||
          _activeUserId != userId) {
        return;
      }
      final remoteName = snapshot.preferences['fontScale']?.toString();
      if (remoteName == null || remoteName.isEmpty) {
        final switchedAccount =
            previousUserId != null && previousUserId != userId;
        _lastBoundUserId = userId;
        if (switchedAccount) {
          // 新账号云端尚无偏好：保留本机呈现即可，禁止把上一账号的选择
          // 反向写成新账号的云端设置。
          return;
        }
        await service.patch(
          userId: userId,
          scope: appearancePreferenceScope,
          changes: {'schemaVersion': 1, 'fontScale': state.name},
        );
        return;
      }
      _lastBoundUserId = userId;
      final resolved = FontScalePreset.fromName(remoteName);
      state = resolved;
      await _writeDevicePreset(resolved);
    } on Object {
      // 离线或无同步依赖注入时静默保留本地偏好。
    }
  }

  PreferenceSyncService? _tryReadSyncService() {
    if (!ref.mounted) {
      return null;
    }
    try {
      return ref.read(preferenceSyncServiceProvider);
    } on Object {
      return null;
    }
  }

  Future<void> _writeDevicePreset(FontScalePreset preset) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(appearanceDeviceFontScaleKey, preset.name);
  }
}
