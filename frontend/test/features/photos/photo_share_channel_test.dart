import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/platform/photo_share_channel.dart';

void main() {
  test('未接入 SDK 时微信分享返回 Unsupported', () async {
    const channel = UnsupportedPhotoShareChannel();
    expect(channel.supportsWeChat, isFalse);
    final result = await channel.shareLinkToWeChat(
      title: 't',
      webUrl: 'https://example.com/share/abc',
    );
    expect(result, isA<PhotoShareChannelUnsupported>());
  });
}
