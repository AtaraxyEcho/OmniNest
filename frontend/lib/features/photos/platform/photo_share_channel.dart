import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// 分享渠道抽象：业务层只依赖本接口，平台实现各自接入系统分享或降级。
abstract class PhotoShareChannel {
  /// 本平台是否提供系统分享入口（移动端系统选择器 / Web 移动浏览器
  /// 的 Web Share API；Web 端 defaultTargetPlatform 反映浏览器宿主系统）。
  bool get supportsSystemShare;

  /// 将分享链接交给系统分享入口；用户可在选择器中选取微信等任意应用。
  Future<PhotoShareChannelResult> shareLink({
    required String title,
    required String url,
  });
}

/// 分享渠道调用结果。
sealed class PhotoShareChannelResult {
  const PhotoShareChannelResult();
}

class PhotoShareChannelSuccess extends PhotoShareChannelResult {
  const PhotoShareChannelSuccess();
}

class PhotoShareChannelUnsupported extends PhotoShareChannelResult {
  const PhotoShareChannelUnsupported(this.reason);

  final String reason;
}

class PhotoShareChannelFailure extends PhotoShareChannelResult {
  const PhotoShareChannelFailure(this.message);

  final String message;
}

/// 基于 share_plus 的系统分享实现：Android/iOS 弹应用选择器，Web 移动
/// 浏览器走 Web Share API；不可用时返回 [PhotoShareChannelUnsupported]，
/// 由 UI 降级复制链接。
class SharePlusPhotoShareChannel implements PhotoShareChannel {
  const SharePlusPhotoShareChannel();

  @override
  bool get supportsSystemShare => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };

  @override
  Future<PhotoShareChannelResult> shareLink({
    required String title,
    required String url,
  }) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(text: url, title: title),
      );
      // share_plus 在环境不支持（桌面浏览器无 Web Share API、测试无插件）
      // 时不抛错而是返回 unavailable 状态，统一转成不可用降级。
      if (result.status == ShareResultStatus.success) {
        return const PhotoShareChannelSuccess();
      }
      return PhotoShareChannelUnsupported(
        'system share unavailable: ${result.status.name}',
      );
    } on Object catch (error) {
      // 保留原因由调用方决定降级提示。
      return PhotoShareChannelUnsupported('system share failed: $error');
    }
  }
}

/// 默认降级实现：无系统分享入口的平台（桌面端）。
class UnsupportedPhotoShareChannel implements PhotoShareChannel {
  const UnsupportedPhotoShareChannel();

  @override
  bool get supportsSystemShare => false;

  @override
  Future<PhotoShareChannelResult> shareLink({
    required String title,
    required String url,
  }) async {
    return const PhotoShareChannelUnsupported(
      'System share is not available on this platform',
    );
  }
}

/// 当前平台的分享渠道（getter 形式保证测试的平台覆写即时生效）。
PhotoShareChannel get photoShareChannel => _resolvePhotoShareChannel();

PhotoShareChannel _resolvePhotoShareChannel() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS => const SharePlusPhotoShareChannel(),
    _ => const UnsupportedPhotoShareChannel(),
  };
}
