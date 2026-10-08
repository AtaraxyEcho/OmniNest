// 采样器的失败面：取不到图时必须外抛，由 provider 兜成暗基准，
// 不能静默返回一个"看起来像暗"的亮度值。
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_tone_sampler.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_tone.dart';

void main() {
  testWidgets('无法解析的 URL 外抛而不是挂住', (tester) async {
    await expectLater(
      sampleAppBackdropTone('http://127.0.0.1:1/missing.png'),
      throwsA(isA<Object>()),
    );
  });

  test('兜底亮度落在暗基准', () {
    const fallback = AppBackdropTone(topLuminance: 0, bottomLuminance: 0);
    expect(fallback.polarity, AppBackdropPolarity.dark);
  });
}
