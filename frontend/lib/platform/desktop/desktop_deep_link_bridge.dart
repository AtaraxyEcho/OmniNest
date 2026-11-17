/// 桌面深链桥：第二实例转发的 omninest:// 链接经此交给 DeepLinkService。
typedef DesktopDeepLinkHandler = void Function(Uri uri);

/// 由深链服务在启动时注册。
DesktopDeepLinkHandler? desktopDeepLinkHandler;
