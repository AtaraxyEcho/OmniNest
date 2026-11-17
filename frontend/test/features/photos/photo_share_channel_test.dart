import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/platform/photo_share_channel.dart';

void main() {
  test('移动平台提供系统分享入口，插件不可用时返回 Unsupported', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(photoShareChannel.supportsSystemShare, isTrue);
    final result = await photoShareChannel.shareLink(
      title: 't',
      url: 'https://example.com/share/abc',
    );
    // 测试环境无 share_plus 插件实现：统一降级为不可用。
    expect(result, isA<PhotoShareChannelUnsupported>());
  });

  test('桌面平台无系统分享入口', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(photoShareChannel.supportsSystemShare, isFalse);
    final result = await photoShareChannel.shareLink(
      title: 't',
      url: 'https://example.com/share/abc',
    );
    expect(result, isA<PhotoShareChannelUnsupported>());
  });
}
