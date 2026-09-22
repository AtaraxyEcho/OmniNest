import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 前台通知提示开关的本地存储。属设备级 UX 偏好，不跨端同步。
class NotificationForegroundPreferenceStore {
  const NotificationForegroundPreferenceStore();

  static const _enabledKey = 'notification_foreground_toast_enabled';
  static const bool defaultEnabled = true;

  Future<bool> loadEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey) ?? defaultEnabled;
  }

  Future<void> saveEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, enabled);
  }
}

final notificationForegroundPreferenceStoreProvider =
    Provider<NotificationForegroundPreferenceStore>((ref) {
      return const NotificationForegroundPreferenceStore();
    });

/// 前台通知提示开关，默认开启。
final notificationForegroundToastEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(notificationForegroundPreferenceStoreProvider).loadEnabled();
});

/// 前台通知事件广播：实时订阅侧单点写入，根部件消费展示轻量提示。
/// 单订阅的 STOMP 流由既有订阅 provider 独占，经此广播流转发避免二次
/// 监听。
final notificationForegroundEventControllerProvider =
    Provider<StreamController<NotificationDto>>((ref) {
      final controller = StreamController<NotificationDto>.broadcast();
      ref.onDispose(controller.close);
      return controller;
    });

final notificationForegroundEventsStreamProvider =
    StreamProvider<NotificationDto>((ref) {
      return ref.watch(notificationForegroundEventControllerProvider).stream;
    });
