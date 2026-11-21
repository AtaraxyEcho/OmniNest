import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_skin.dart';

/// 桌面深浅色板逐值对齐原型 `desktop.css:18-36`。
///
/// 用户反馈的「深浅模式颜色不一致」先由这里排掉令牌漂移；真实观感偏差若
/// 仍存在，就只剩环境光/覆盖层级这类合成问题，不应再手改语义色。
void main() {
  test('桌面暗色令牌与样例一致', () {
    final skin = DesktopSkin.resolve(isDark: true, accent: DesktopAccent.sage);
    expect(skin.bg, const Color(0xFF0B0E11));
    expect(skin.bg2, const Color(0xFF11151A));
    expect(skin.panelSolid, const Color(0xFF161B20));
    expect(skin.panel.a, closeTo(0.66, 0.005));
    expect(skin.text, const Color(0xFFE8ECEA));
    expect(skin.text2, const Color(0xFFA3ADAA));
    expect(skin.text3, const Color(0xFF68726F));
    expect(skin.accent, const Color(0xFF8CC5B2));
    expect(skin.accentInk, const Color(0xFF0A1411));
    expect(skin.warm, const Color(0xFFD9B48A));
    expect(skin.veil.a, closeTo(0.72, 0.005));
  });

  test('桌面浅色令牌与样例一致', () {
    final skin = DesktopSkin.resolve(isDark: false, accent: DesktopAccent.sage);
    expect(skin.bg, const Color(0xFFEEF0EC));
    expect(skin.bg2, const Color(0xFFE6E9E4));
    expect(skin.panelSolid, const Color(0xFFFBFCFA));
    expect(skin.panel.a, closeTo(0.66, 0.005));
    expect(skin.text, const Color(0xFF19211E));
    expect(skin.text2, const Color(0xFF526059));
    expect(skin.text3, const Color(0xFF8A9690));
    expect(skin.accent, const Color(0xFF2F7A68));
    expect(skin.accentInk, const Color(0xFFFFFFFF));
    expect(skin.warm, const Color(0xFF9A6A3A));
    expect(skin.veil.a, closeTo(0.80, 0.005));
  });
}
