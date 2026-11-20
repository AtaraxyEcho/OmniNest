import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_glass.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('外侧投影不给透明填充染底色', (tester) async {
    tester.view.physicalSize = const Size(400, 440);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const captureKey = ValueKey<String>('outset-shadow');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: captureKey,
          child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: Center(
              // 圆角 26 + spread -34：与首页 Hero 同一条 CSS 阴影
              // （`polish.css:451` 的 `0 30px 70px -34px rgba(0,0,0,.55)`）。
              child: DesktopOutsetShadow(
                borderRadius: BorderRadius.circular(26),
                shadows: const [
                  BoxShadow(
                    color: Color(0x8C000000),
                    blurRadius: 70,
                    spreadRadius: -34,
                    offset: Offset(0, 30),
                  ),
                ],
                child: const SizedBox(width: 300, height: 200),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(captureKey),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    // 盒子居中：x 50–350、y 120–320。
    final inside = _pixel(bytes!, 400, 200, 140);
    final leftInside = _pixel(bytes, 400, 60, 220);
    final below = _pixel(bytes, 400, 200, 340);

    expect(inside, const Color(0xFFFFFFFF), reason: '盒内必须完全透出底色，黑纱会把它压成灰色');
    expect(
      leftInside,
      const Color(0xFFFFFFFF),
      reason: '负 spread 把阴影形状缩在盒内，外扩模糊带不得从内侧边缘渗入',
    );
    expect(
      below,
      isNot(const Color(0xFFFFFFFF)),
      reason: '边框盒外侧仍要保留投影，否则这层等价于没画阴影',
    );
  });
}

Color _pixel(ByteData bytes, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return Color.fromARGB(
    bytes.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}
