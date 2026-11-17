// 桌面壳层引导门面：IO 平台启用托盘/单实例，Web 与移动端空实现。
export 'desktop_shell_bootstrap_stub.dart'
    if (dart.library.io) 'desktop_shell_bootstrap_io.dart';
