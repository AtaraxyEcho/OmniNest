import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';

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
