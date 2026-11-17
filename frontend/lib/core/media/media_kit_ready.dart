import 'package:media_kit/media_kit.dart';

bool _ready = false;

/// 视频原生库只在第一次真正创建 `Player` 之前初始化。
///
/// 启动关键路径上串行加载视频原生库（Android/iOS 的 libmpv、Windows 的
/// 解码器）会推迟首帧，而绝大多数会话根本不进视频页；把初始化下沉到
/// 第一条视频路径，首帧不再陪跑。音乐侧是 SoLoud，不经过这里。
///
/// 调用点必须是**每一处** `Player()` 之前；漏一处会在真机上直接崩。
void ensureMediaKitReady() {
  if (_ready) {
    return;
  }
  MediaKit.ensureInitialized();
  _ready = true;
}
