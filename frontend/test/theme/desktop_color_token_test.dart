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
    expect(skin.panel, const Color(0xFF161B20).withValues(alpha: 0.66));
    expect(skin.card, const Color(0xFF0E1216).withValues(alpha: 0.58));
    expect(skin.text, const Color(0xFFEEF2F0));
    expect(skin.text2, const Color(0xFFB1BBB8));
    expect(skin.text3, const Color(0xFF86918D));
    expect(skin.accent, const Color(0xFF8CC5B2));
    expect(skin.accentInk, const Color(0xFF0A1411));
    expect(skin.warm, const Color(0xFFD9B48A));
    expect(skin.veil.a, closeTo(0.72, 0.005));
    expect(DesktopPalette.danger, const Color(0xFFC9534B));
  });

  test('桌面浅色令牌与样例一致', () {
    final skin = DesktopSkin.resolve(isDark: false, accent: DesktopAccent.sage);
    expect(skin.bg, const Color(0xFFF5F4EF));
    expect(skin.bg2, const Color(0xFFECEBE4));
    expect(skin.panelSolid, const Color(0xFFFFFFFF));
    expect(skin.panel, const Color(0xFFFFFFFF).withValues(alpha: 0.78));
    expect(skin.card, const Color(0xFFF5F4EF).withValues(alpha: 0.55));
    expect(skin.text, const Color(0xFF0F1613));
    expect(skin.text2, const Color(0xFF2C3832));
    expect(skin.text3, const Color(0xFF46524B));
    expect(skin.accent, const Color(0xFF266B5A));
    expect(skin.accentInk, const Color(0xFFFFFFFF));
    expect(skin.warm, const Color(0xFF85582C));
    expect(skin.veil, const Color(0xFFF6F5F0).withValues(alpha: 0.90));
  });
}
