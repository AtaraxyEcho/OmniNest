import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:omninest/platform/platform_capabilities.dart';

/// 通用系统通知器：后台任务完成/失败等场景的系统级通知。
///
/// 能力由 [PlatformCapabilities.supportsSystemNotifications] 驱动：
/// Android/iOS/macOS/Linux 生效；Web 与 Windows 为空操作
/// （flutter_local_notifications 0.18 不覆盖 Windows，任务提醒走站内）。
class SystemNotifier {
  SystemNotifier._();

  static final SystemNotifier instance = SystemNotifier._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  bool get isSupported =>
      PlatformCapabilities.current().supportsSystemNotifications;

  Future<void> initialize() async {
    if (_initialized || !isSupported) {
      return;
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
      linux: LinuxInitializationSettings(defaultActionName: '确定'),
    );
    try {
      await _plugin.initialize(settings);
      final android =
          _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      // Android 13+ 运行时通知权限（清单已声明 POST_NOTIFICATIONS）。
      await android?.requestNotificationsPermission();
      _initialized = true;
    } on Exception {
      // 初始化失败（无 Google 服务等）不阻塞应用，仅关闭通知能力。
      _initialized = true;
    }
  }

  /// 发送系统通知；[id] 用于区分可更新通知（取任务 id 哈希）。
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!isSupported) {
      return;
    }
    await initialize();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'omninest_tasks',
        '后台任务',
        channelDescription: '上传、下载、扫描等后台任务的完成与失败提醒',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
    try {
      await _plugin.show(id, title, body, details);
    } on Exception {
      // 单条通知失败静默忽略，不影响任务本身。
    }
  }
}
