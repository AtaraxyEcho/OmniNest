import 'package:flutter/material.dart';

/// 桌面/Web 端设计稿色板。
///
/// 逐值对应桌面样例 `src/desktop/desktop.css` 的 `.root[data-theme]` 令牌，
/// 与移动端色板完全分离：移动壳层不读本文件，桌面重构因此不会漂移到手机。
///
/// 强调色档位逐值取自样例 `Settings.tsx:14`，包括样例明确提供的 Iris 选项。
abstract final class DesktopPalette {
  // ── 强调色档（样例 Settings.tsx accents，四档）──────────────────────
  static const Color sageDark = Color(0xFF8CC5B2);
  static const Color sageLight = Color(0xFF2F7A68);
  static const Color mistDark = Color(0xFF8FB2D6);
  static const Color mistLight = Color(0xFF3A6EA0);
  static const Color copperDark = Color(0xFFD6A67A);
  static const Color copperLight = Color(0xFFA2662F);
  static const Color irisDark = Color(0xFFA99BD8);
  static const Color irisLight = Color(0xFF6A58B0);

  // ── 深色主题 ────────────────────────────────────────────────────────
  static const Color bgDark = Color(0xFF0B0E11);
  static const Color bg2Dark = Color(0xFF11151A);

  /// 登录页深色样例的右上角径向起始色（`desktop.css:494`）。
  static const Color authGlowDark = Color(0xFF14201D);
  static const Color panelSolidDark = Color(0xFF161B20);

  /// `.drawer` 通用左侧阴影。
  static const Color drawerShadow = Color(0x99000000);
  static const Color popBaseDark = Color(0xFF1A2026);
  static const Color textDark = Color(0xFFE8ECEA);
  static const Color text2Dark = Color(0xFFA3ADAA);
  static const Color text3Dark = Color(0xFF68726F);
  static const Color accentInkDark = Color(0xFF0A1411);
  static const Color warmDark = Color(0xFFD9B48A);
  static const Color veilDark = Color(0xFF080B0E);
  static const Color raiseBaseDark = Color(0xFFFFFFFF);
  static const Color shadowDark = Color(0xA6000000);
  static const Color shadowSoftDark = Color(0x4D000000);

  // ── 浅色主题 ────────────────────────────────────────────────────────
  static const Color bgLight = Color(0xFFEEF0EC);
  static const Color bg2Light = Color(0xFFE6E9E4);
  static const Color panelSolidLight = Color(0xFFFBFCFA);
  // `--panel` 的浅色基色是纯白，与 `--panel-solid` 的 #FBFCFA 不是同一档。
  static const Color panelBaseLight = Color(0xFFFFFFFF);
  static const Color popBaseLight = Color(0xFFFCFDFB);
  static const Color textLight = Color(0xFF19211E);
  static const Color text2Light = Color(0xFF526059);
  static const Color text3Light = Color(0xFF8A9690);
  static const Color accentInkLight = Color(0xFFFFFFFF);
  static const Color warmLight = Color(0xFF9A6A3A);
  static const Color veilLight = Color(0xFFEEF0EC);
  static const Color raiseBaseLight = Color(0xFF18241E);
  static const Color shadowLight = Color(0x59283730);
  static const Color shadowSoftLight = Color(0x1A283730);

  /// 弹窗/抽屉遮罩（样例 `--scrim-bg: rgba(4,7,9,.4)`）。
  static const Color scrim = Color(0x66040809);

  /// 已有一层弹层时的浅遮罩（样例 `desktop.css:140` 的 `.2` alpha）。
  static const Color scrimNested = Color(0x33040809);

  // ── 语义色（样例 .tag / .toast / .btn.danger）───────────────────────
  static const Color ok = Color(0xFF7FCF9F);
  static const Color okSeed = Color(0xFF6FBF8F);
  static const Color warn = Color(0xFFE0A05A);
  static const Color bad = Color(0xFFE57A74);
  static const Color badSeed = Color(0xFFE0655F);
  static const Color info = Color(0xFF7FB0E0);
  static const Color danger = Color(0xFFC25B55);
  static const Color liked = Color(0xFFE0777A);
  static const Color likedImmersive = Color(0xFFFF6B8B);

  // ── 文件类别色（样例 desktop.css `.fi`）───────────────────────────
  static const Color kindFolder = Color(0xFFD6A67A);
  static const Color kindDocument = Color(0xFFD98E88);
  static const Color kindVideo = Color(0xFFD9B46C);
  static const Color kindAudio = Color(0xFF7DBCC9);
  static const Color kindImage = Color(0xFF8CC5A2);
  static const Color kindText = Color(0xFFA9A4D6);

  /// 存储分布图的类别色，对应样例 `data.ts:157` 的固定类别色。
  static const Color storageVideo = Color(0xFFC58C5C);
  static const Color storagePhotos = Color(0xFF6F9A93);
  static const Color storageMusic = Color(0xFF8B7AA5);
  static const Color storageDocuments = Color(0xFF6D8BB0);

  // ── 环境光斑（样例 .blob.b3）───────────────────────────────────────
  static const Color ambientCool = Color(0xFF5D6FA8);

  /// 样例 `.grain` 的 5% 叠加噪点。
  static const Color grain = Color(0x0DFFFFFF);

  /// hero 的两道压暗（样例 `.sky-shade`），保证白字在任何天象上可读。
  static const Color heroShade = Color(0x8C050A12);
  static const Color heroShadeSoft = Color(0x80050A12);
  static const Color heroShadeClear = Color(0x00050A12);

  // ── 沉浸舞台（样例 .video / .viewer / .np 的固定暗底）───────────────
  static const Color stageBlack = Color(0xFF05080A);
  static const Color playerBlack = Color(0xFF07090B);
  static const Color onStage = Color(0xFFFFFFFF);

  // ── 阅读器纸张（样例 .bookview 三档）───────────────────────────────
  static const Color paperPlain = Color(0xFFF6F1E4);
  static const Color inkPlain = Color(0xFF2B2620);
  static const Color deskPlain = Color(0xFF1B1F22);
  static const Color paperEdgePlain = Color(0xFFE4DCC8);
  static const Color paperSepia = Color(0xFFEAD9B6);
  static const Color inkSepia = Color(0xFF3D2F1B);
  static const Color deskSepia = Color(0xFF2A2118);
  static const Color paperEdgeSepia = Color(0xFFD6C196);
  static const Color paperNight = Color(0xFF1C2024);
  static const Color inkNight = Color(0xFFC9CDC8);
  static const Color deskNight = Color(0xFF0B0D0F);
  static const Color paperEdgeNight = Color(0xFF14171A);

  // ── 头像与人物（样例 .cast i / .avatar.sm）─────────────────────────
  static const Color portrait = Color(0xFFD6C0A9);
  static const Color portraitInk = Color(0xFF2C211A);

  // ── 高亮批注（样例 Reader.tsx .hl --c）─────────────────────────────
  static const Color highlightAmber = Color(0xFFF2D36B);

  // ── 首页天象（样例 Sky.tsx 的时段渐变与降水配色）───────────────────
  static const Color skyNightTop = Color(0xFF070B16);
  static const Color skyNightMid = Color(0xFF111A2E);
  static const Color skyNightLow = Color(0xFF1D2A40);
  static const Color skyDawnTop = Color(0xFF2A3550);
  static const Color skyDawnMid = Color(0xFFA77F78);
  static const Color skyDawnLow = Color(0xFFE4B48C);
  static const Color skyDayTop = Color(0xFF3D6F9E);
  static const Color skyDayMid = Color(0xFF7FA9C8);
  static const Color skyDayLow = Color(0xFFCFE0E6);
  static const Color skyDuskTop = Color(0xFF2C3E66);
  static const Color skyDuskMid = Color(0xFFA8728A);
  static const Color skyDuskLow = Color(0xFFEFAC7A);
  static const Color skyLateTop = Color(0xFF3A4766);
  static const Color skyLateMid = Color(0xFF6B6A86);
  static const Color skyLateLow = Color(0xFFA58A8C);
  static const Color skyOvercastDay = Color(0xFF7B8793);
  static const Color skyOvercastNight = Color(0xFF161D2A);
  static const Color sunGlow = Color(0xFFFFD696);
  static const Color sunBody = Color(0xFFFFE7BD);
  static const Color moonGlow = Color(0xFFBECDFF);
  static const Color moonBody = Color(0xFFE8EEFF);
  static const Color cloudHeavyDay = Color(0xFF96A0AF);
  static const Color cloudLightDay = Color(0xFFFFFFFF);
  static const Color cloudHeavyNight = Color(0xFF374054);
  static const Color cloudLightNight = Color(0xFF5A6482);
  static const Color fogDay = Color(0xFFE1E8EC);
  static const Color fogNight = Color(0xFF465268);
  static const Color precipitation = Color(0xFFC8D7EB);
  static const Color ridgeFarDay = Color(0xFF4A6A7C);
  static const Color ridgeMidDay = Color(0xFF2F4A58);
  static const Color ridgeNearDay = Color(0xFF1B2F3A);
  static const Color ridgeFarNight = Color(0xFF101A2C);
  static const Color ridgeMidNight = Color(0xFF0B1220);
  static const Color ridgeNearNight = Color(0xFF070D17);

  /// 图书纸封的取色轮转：样例给每本书一个 tone/ink，真实书目没有这两个
  /// 字段，按 id 稳定取色，同一本书每次进页面颜色不变。
  static const List<({Color tone, Color ink})> bookTones = [
    (tone: Color(0xFFC9B97F), ink: Color(0xFF2B2924)),
    (tone: Color(0xFF8F988D), ink: Color(0xFF161C19)),
    (tone: Color(0xFFC4AEA2), ink: Color(0xFF2C211A)),
    (tone: Color(0xFFD5CCAD), ink: Color(0xFF2C2C26)),
    (tone: Color(0xFF9FB3A8), ink: Color(0xFF17211C)),
    (tone: Color(0xFFD8C3A5), ink: Color(0xFF2E2419)),
  ];

  /// 按稳定标识取纸封配色。
  static ({Color tone, Color ink}) bookToneFor(String id) {
    var hash = 7;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return bookTones[hash % bookTones.length];
  }
}

/// 桌面强调色档位。
enum DesktopAccent {
  sage('Sage', DesktopPalette.sageDark, DesktopPalette.sageLight),
  mist('Mist', DesktopPalette.mistDark, DesktopPalette.mistLight),
  copper('Copper', DesktopPalette.copperDark, DesktopPalette.copperLight),
  iris('Iris', DesktopPalette.irisDark, DesktopPalette.irisLight);

  const DesktopAccent(this.label, this.dark, this.light);

  /// 档位名，用于设置页色板与持久化键。
  final String label;
  final Color dark;
  final Color light;

  Color resolve({required bool isDark}) => isDark ? dark : light;

  static DesktopAccent fromName(String? name) {
    return DesktopAccent.values.firstWhere(
      (accent) => accent.name == name,
      orElse: () => DesktopAccent.sage,
    );
  }
}
