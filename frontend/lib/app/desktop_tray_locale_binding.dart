// 桌面托盘语言绑定门面：IO 平台启用托盘刷新，Web 为空实现。
// tray_manager 0.7 依赖 nativeapi(dart:ffi)，Web 编译禁止触达该链路。
export 'desktop_tray_locale_binding_stub.dart'
    if (dart.library.io) 'desktop_tray_locale_binding_io.dart';
