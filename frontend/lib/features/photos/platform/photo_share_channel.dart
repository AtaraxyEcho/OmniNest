import 'package:flutter/foundation.dart';

/// 分享渠道抽象：业务层只依赖本接口，平台实现各自接入 SDK 或降级。
abstract class PhotoShareChannel {
  /// 是否可在本平台调起微信网页分享。
  bool get supportsWeChat;

  /// 将分享链接送到微信（网页卡片）。
  ///
  /// [webUrl] 必须为公网可达的绝对地址；[thumbUrl] 可选封面。
  Future<PhotoShareChannelResult> shareLinkToWeChat({
    required String title,
    required String webUrl,
    String? thumbUrl,
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

/// 默认降级实现：未接入微信 SDK 时统一返回不可用，由 UI 复制链接/展示说明。
class UnsupportedPhotoShareChannel implements PhotoShareChannel {
  const UnsupportedPhotoShareChannel();

  @override
  bool get supportsWeChat => false;

  @override
  Future<PhotoShareChannelResult> shareLinkToWeChat({
    required String title,
    required String webUrl,
    String? thumbUrl,
  }) async {
    return const PhotoShareChannelUnsupported(
      'WeChat share SDK is not configured on this platform',
    );
  }
}

/// 当前平台的分享渠道。
final PhotoShareChannel photoShareChannel = _resolvePhotoShareChannel();

PhotoShareChannel _resolvePhotoShareChannel() {
  // Android/iOS 接入 fluwx 后在此切换；Web/Desktop 保持降级。
  if (kIsWeb) {
    return const UnsupportedPhotoShareChannel();
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS => const UnsupportedPhotoShareChannel(),
    _ => const UnsupportedPhotoShareChannel(),
  };
}
