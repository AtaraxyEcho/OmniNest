import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // 与 Windows/Linux 兜底值一致；Dart 侧 WindowGeometryService 启动后
    // 会按记忆边界或工作区重新摆放。
    let windowFrame = NSRect(x: 0, y: 0, width: 1280, height: 800)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 保留 macOS 原生缩放/最小化丝滑动画与阴影，同时允许自绘标题栏铺满顶部。
    self.styleMask.insert(.fullSizeContentView)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
