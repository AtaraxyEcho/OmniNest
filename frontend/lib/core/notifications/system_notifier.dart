import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:omninest/platform/platform_capabilities.dart';

/// 系统通知点击后的路由处理回调。
typedef NotificationTapRouteHandler = void Function(String route);

/// 通知点击落位回调，由 [systemNotificationTapBindingProvider] 注入。
///
/// 与桌面第二实例的 `desktopDeepLinkHandler` 同一模式：core 侧只负责把
/// 平台回调转成路由意图，具体导航动作由应用根的绑定持有，避免 core 依赖
/// GoRouter。
NotificationTapRouteHandler? notificationTapRouteHandler;

/// 系统通知点击后的落位路由。
///
/// 通知栏只把用户带回通知中心；按任务类型直达业务对象的跳转由中心内
/// 条目行动链承担，避免把内部任务语义暴露到系统通知栏。
const String notificationTapRoute = '/notifications';

/// 通用系统通知器：后台任务完成/失败等场景的系统级通知。
///
/// 能力由 [PlatformCapabilities.supportsSystemNotifications] 驱动：
/// Android/iOS/macOS/Linux 生效；Web 与 Windows 暂为空操作
/// （库自 19.0 起支持 Windows、22.0 起支持 Web，平台能力开关尚未放开）。
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
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );
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

  /// 处理通知栏点击：仅响应“选中通知”，忽略动作与清除。
  void _handleNotificationResponse(NotificationResponse response) {
    if (response.notificationResponseType !=
        NotificationResponseType.selectedNotification) {
      return;
    }
    notificationTapRouteHandler?.call(notificationTapRoute);
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
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } on Exception {
      // 单条通知失败静默忽略，不影响任务本身。
    }
  }
}
