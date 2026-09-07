import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/appearance/application/appearance_controller.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用字体档位。跟随系统不覆盖环境 TextScaler，其余档位以线性倍率
/// 与系统缩放组合应用。
enum FontScalePreset {
  followSystem(null),
  compact(0.9),
  standard(1.0),
  comfortable(1.15),
  large(1.3);

  const FontScalePreset(this.scale);

  final double? scale;

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
  int _loadGeneration = 0;

  @override
  FontScalePreset build() {
    final initial = FontScalePreset.fromName(
      ref.read(appBootstrapDataProvider).fontScaleName,
    );
    ref.listen(authSessionProvider, (_, next) {
      final userId = next.asData?.value.user?.id;
      unawaited(_bindUser(userId));
    }, fireImmediately: true);
    return initial;
  }

  Future<void> setPreset(FontScalePreset preset) async {
    state = preset;
    await _writeDevicePreset(preset);
    final userId = _activeUserId;
    if (userId == null) {
      return;
    }
    await ref
        .read(preferenceSyncServiceProvider)
        .patch(
          userId: userId,
          scope: appearancePreferenceScope,
          changes: {'schemaVersion': 1, 'fontScale': preset.name},
        );
  }

  /// 从远端重新同步字体档位，并保留本地待提交变更。
  Future<void> refreshFromRemote() async {
    final userId = _activeUserId;
    if (userId == null) return;
    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .synchronize(userId: userId, scope: appearancePreferenceScope);
    if (_activeUserId != userId) return;
    final resolved = FontScalePreset.fromName(
      snapshot.preferences['fontScale']?.toString(),
    );
    state = resolved;
    await _writeDevicePreset(resolved);
  }

  Future<void> _bindUser(String? userId) async {
    _activeUserId = userId;
    final generation = ++_loadGeneration;
    if (userId == null) {
      final preferences = await SharedPreferences.getInstance();
      if (generation == _loadGeneration) {
        state = FontScalePreset.fromName(
          preferences.getString(appearanceDeviceFontScaleKey),
        );
      }
      return;
    }

    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .load(userId: userId, scope: appearancePreferenceScope);
    if (generation != _loadGeneration || _activeUserId != userId) {
      return;
    }
    final remoteName = snapshot.preferences['fontScale']?.toString();
    if (remoteName == null || remoteName.isEmpty) {
      await ref
          .read(preferenceSyncServiceProvider)
          .patch(
            userId: userId,
            scope: appearancePreferenceScope,
            changes: {'schemaVersion': 1, 'fontScale': state.name},
          );
      return;
    }
    final resolved = FontScalePreset.fromName(remoteName);
    state = resolved;
    await _writeDevicePreset(resolved);
  }

  Future<void> _writeDevicePreset(FontScalePreset preset) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(appearanceDeviceFontScaleKey, preset.name);
  }
}
