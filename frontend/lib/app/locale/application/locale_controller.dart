import 'dart:async';

import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/errors/user_facing_error_locale.dart';
import 'package:shared_preferences/shared_preferences.dart';

const localePreferenceScope = 'locale.v1';
const supportedLanguageCodes = {'zh', 'en'};

/// 无已存偏好时的默认语言：跟随系统语言，不支持的语言回退中文。
/// 经 WidgetsBinding 读取，保证与 Widget 层可见的 locale 一致。
String resolveSystemLanguage() {
  final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  return supportedLanguageCodes.contains(code) ? code : 'zh';
}

final localeControllerProvider = NotifierProvider<LocaleController, String>(
  LocaleController.new,
);

class LocaleController extends Notifier<String> {
  String? _activeUserId;

  /// 上一次绑定的非空账号：用于识别"换号"，避免把上一账号的设备偏好回写到新账号云端。
  String? _lastBoundUserId;
  int _loadGeneration = 0;

  @override
  String build() {
    final initial = _normalizeLanguage(
      ref.read(appBootstrapDataProvider).languageCode,
    );
    ref.listen(authSessionProvider, (_, next) {
      final userId = next.value?.user?.id;
      unawaited(_bindUser(userId));
    }, fireImmediately: true);
    return _applyLanguage(initial);
  }

  Future<void> setLanguage(String languageCode) async {
    final resolved = _normalizeLanguage(languageCode);
    state = _applyLanguage(resolved);
    await _writeDeviceLanguage(resolved);
    final userId = _activeUserId;
    if (userId == null) {
      return;
    }
    await ref
        .read(preferenceSyncServiceProvider)
        .patch(
          userId: userId,
          scope: localePreferenceScope,
          changes: {'schemaVersion': 1, 'language': resolved},
        );
  }

  /// 从远端重新同步语言偏好，并保留本地待提交变更。
  Future<void> refreshFromRemote() async {
    final userId = _activeUserId;
    if (userId == null) return;
    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .synchronize(userId: userId, scope: localePreferenceScope);
    if (_activeUserId != userId) return;
    final resolved = _normalizeLanguage(
      snapshot.preferences['language']?.toString(),
    );
    state = _applyLanguage(resolved);
    await _writeDeviceLanguage(resolved);
  }

  Future<void> _bindUser(String? userId) async {
    final previousUserId = _lastBoundUserId;
    _activeUserId = userId;
    final generation = ++_loadGeneration;
    if (userId == null) {
      final preferences = await SharedPreferences.getInstance();
      if (generation == _loadGeneration) {
        state = _applyLanguage(
          _normalizeLanguage(preferences.getString(localeDeviceLanguageKey)),
        );
      }
      return;
    }

    final snapshot = await ref
        .read(preferenceSyncServiceProvider)
        .load(userId: userId, scope: localePreferenceScope);
    if (generation != _loadGeneration || _activeUserId != userId) {
      return;
    }
    final remoteLanguage = snapshot.preferences['language']?.toString();
    if (remoteLanguage == null || remoteLanguage.isEmpty) {
      final switchedAccount =
          previousUserId != null && previousUserId != userId;
      _lastBoundUserId = userId;
      if (switchedAccount) {
        // 新账号云端尚无偏好：保留本机呈现即可，禁止把上一账号的选择
        // 反向写成新账号的云端设置。
        return;
      }
      await ref
          .read(preferenceSyncServiceProvider)
          .patch(
            userId: userId,
            scope: localePreferenceScope,
            changes: {'schemaVersion': 1, 'language': state},
          );
      return;
    }
    _lastBoundUserId = userId;
    final resolved = _normalizeLanguage(remoteLanguage);
    state = _applyLanguage(resolved);
    await _writeDeviceLanguage(resolved);
  }

  /// 记录语言并同步到进程级镜像：控制器层据此解析可展示的错误文案。
  String _applyLanguage(String languageCode) {
    UserFacingErrorLocale.bind(languageCode);
    return languageCode;
  }

  Future<void> _writeDeviceLanguage(String languageCode) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(localeDeviceLanguageKey, languageCode);
    await preferences.remove(legacyGlobalLanguageKey);
  }

  String _normalizeLanguage(String? value) {
    if (value != null && supportedLanguageCodes.contains(value)) {
      return value;
    }
    return resolveSystemLanguage();
  }
}
