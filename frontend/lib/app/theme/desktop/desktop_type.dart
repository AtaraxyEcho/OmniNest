import 'package:material_ui/material_ui.dart';

/// 桌面/Web 端排版令牌。
///
/// 对应样例 `desktop.css` 的 `--ui`（Inter）与 `--serif`（Newsreader），
/// 基准 14px / 行高 1.45 / 字距 -.003em。字号一律走本文件的常量，
/// 业务侧不写裸数字（font_size_lint 闸门）。
abstract final class DesktopType {
  static const String uiFamily = 'Inter';
  static const String serifFamily = 'Newsreader';
  static const String monoFamily = 'JetBrainsMono';

  /// 西文缺字时的中文回落，顺序对应样例 `desktop.css:5` 的 `--ui` 链。
  ///
  /// - `NotoSansSC` 是 pubspec 里登记的随包族名（不带空格），位置等同链中的
  ///   `Noto Sans SC`；写成带空格的名字会找不到随包字体。
  /// - CSS 末尾的 `system-ui` / `sans-serif` 是泛型关键字而不是家族名，Flutter
  ///   里登记它们不会命中任何字体；未命中时本就落到平台默认族，等价收尾。
  static const List<String> uiFallback = <String>[
    'Segoe UI Variable',
    'PingFang SC',
    'Microsoft YaHei UI',
    'NotoSansSC',
  ];

  /// 衬线回落，顺序对应样例 `desktop.css:6` 的 `--serif` 链（`serif` 泛型同上略去）。
  static const List<String> serifFallback = <String>[
    'Songti SC',
    'Source Han Serif SC',
    'NotoSerifSC',
    'Georgia',
  ];

  /// 等宽回落：样例 `desktop.css:481` 的 `ui-monospace, Consolas, monospace`。
  /// 主族仍是随包分发的 JetBrains Mono（`ui-monospace` 在 Flutter 里无对应）。
  static const List<String> monoFallback = <String>['SF Mono', 'Consolas'];

  // ── 字号阶梯（样例实测值）──────────────────────────────────────────
  static const double sizeNano = 9;
  static const double sizeMicro = 10;
  static const double sizeEyebrow = 10.5;
  static const double sizeCaption = 11;
  static const double sizeCaptionPlus = 11.5;
  static const double sizeSmall = 12;
  static const double sizeSmallPlus = 12.5;
  static const double sizeBody = 13;
  static const double sizeBodyPlus = 13.5;
  static const double sizeBase = 14;
  static const double sizeMedium = 15;
  static const double sizeLarge = 16;
  static const double sizePanelTitle = 17;
  static const double sizeTitle = 20;
  static const double sizeDisplaySm = 22;
  static const double sizeSection = 24;

  /// `.fx-crumb b`：文件页面包屑标题 26 衬线（`desktop.css:453`）。
  static const double sizeCrumb = 26;
  static const double sizeStat = 34;
  // `desktop.css:417` 的阅读 insight 与 `extra.css:220` 的管理台统计各有
  // 自己的字号，不能一律沿用首页 statValue。
  static const double sizeStatReader = 28;
  static const double sizeStatAdmin = 30;
  static const double sizeDisplay = 34;
  static const double sizeAuthTitle = 40;
  static const double sizeSplash = 44;
  static const double sizeBigNum = 56;
  static const double sizeDisplayXlMin = 38;
  static const double sizeDisplayXlMax = 64;

  /// `.display.xl` 的 `clamp(38px, 4.2vw, 64px)`。
  static double displayXlSize(double viewportWidth) {
    return (viewportWidth * 0.042).clamp(sizeDisplayXlMin, sizeDisplayXlMax);
  }

  static double _em(double size, double em) => size * em;

  static TextStyle _ui(
    double size,
    Color color, {
    FontWeight weight = FontWeight.w400,
    double? height,
    double tracking = -0.003,
    List<String>? fallback,
  }) {
    return TextStyle(
      fontFamily: uiFamily,
      fontFamilyFallback: fallback ?? uiFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height ?? 1.45,
      letterSpacing: _em(size, tracking),
    );
  }

  static TextStyle _serif(
    double size,
    Color color, {
    FontWeight weight = FontWeight.w400,
    double height = 1.05,
    double tracking = -0.02,
    FontStyle style = FontStyle.normal,
  }) {
    return TextStyle(
      fontFamily: serifFamily,
      fontFamilyFallback: serifFallback,
      fontSize: size,
      fontWeight: weight,
      fontStyle: style,
      color: color,
      height: height,
      letterSpacing: _em(size, tracking),
    );
  }

  // ── 无衬线语义档 ────────────────────────────────────────────────────
  static TextStyle body(Color color) => _ui(sizeBase, color);
  static TextStyle bodyStrong(Color color) =>
      _ui(sizeBase, color, weight: FontWeight.w500);
  static TextStyle dense(Color color) => _ui(sizeBody, color);
  static TextStyle denseStrong(Color color) =>
      _ui(sizeBody, color, weight: FontWeight.w500);
  static TextStyle rowTitle(Color color) =>
      _ui(sizeBodyPlus, color, weight: FontWeight.w500);
  static TextStyle secondary(Color color) => _ui(sizeSmallPlus, color);
  static TextStyle caption(Color color) => _ui(sizeSmall, color);
  static TextStyle micro(Color color) => _ui(sizeCaption, color);
  static TextStyle nano(Color color) => _ui(sizeNano, color);
  static TextStyle medium(Color color) => _ui(sizeMedium, color);
  static TextStyle panelTitle(Color color) =>
      _ui(sizePanelTitle, color, weight: FontWeight.w600);
  static TextStyle cardTitle(Color color) =>
      _ui(sizeMedium, color, weight: FontWeight.w600, height: 1.35);

  /// Reader 封面标题：对应样例 `.book-cover b` 的衬线标题层级。
  static TextStyle coverTitle(Color color, {bool large = false}) =>
      _serif(large ? sizeDisplaySm : sizeLarge, color, height: 1.12);

  /// 文件页面包屑标题：衬线 26 / 字距 -.015em。
  static TextStyle crumbTitle(Color color) =>
      _serif(sizeCrumb, color, height: 1.2, tracking: -0.015);
  static TextStyle button(Color color) =>
      _ui(sizeBody, color, weight: FontWeight.w500, height: 1.2);
  static TextStyle buttonLarge(Color color) =>
      _ui(sizeBase, color, weight: FontWeight.w500, height: 1.2);

  /// `.tag`：11 / 550 的只读标签胶囊。
  static TextStyle chip(Color color) =>
      _ui(sizeCaption, color, weight: FontWeight.w500, height: 1.2);

  /// `.chip-btn`：12.5 / 500 的可点筛选胶囊。
  static TextStyle chipButton(Color color) =>
      _ui(sizeSmallPlus, color, weight: FontWeight.w500, height: 1.2);
  static TextStyle navItem(Color color) =>
      _ui(sizeBase, color, weight: FontWeight.w500, height: 1.2);
  static TextStyle navSub(Color color) =>
      _ui(sizeBody, color, weight: FontWeight.w400, height: 1.2);
  static TextStyle link(Color color) =>
      _ui(sizeSmallPlus, color, weight: FontWeight.w500, height: 1.2);
  static TextStyle field(Color color) => _ui(sizeBase, color);
  static TextStyle fieldLabel(Color color) =>
      _ui(sizeSmall, color, weight: FontWeight.w500);

  /// `.sf-hint` / `.sf-err` / `.field .hint`：字段辅助行 11.5。
  static TextStyle fieldHint(Color color) => _ui(sizeCaptionPlus, color);

  /// `.eyebrow`：10.5 / 600 / +.14em / 大写由调用方处理。
  ///
  /// 样例没有给 `.eyebrow` 单独写行高，它继承根上的 1.45（`desktop.css:11`）。
  static TextStyle eyebrow(Color color) => _ui(
    sizeEyebrow,
    color,
    weight: FontWeight.w600,
    height: 1.45,
    tracking: 0.14,
  );

  /// 表头 `.t-head` / `.col`：11 / 600 / +.1em。
  static TextStyle tableHead(Color color) =>
      _ui(sizeCaption, color, weight: FontWeight.w600, tracking: 0.1);

  static TextStyle kbd(Color color) =>
      _ui(sizeEyebrow, color, weight: FontWeight.w500, height: 1.2);

  static TextStyle mono(Color color) => TextStyle(
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    fontSize: sizeSmall,
    color: color,
    height: 1.6,
  );

  /// 时间/进度等等宽数字位。
  static TextStyle numeric(Color color) => _ui(
    sizeCaptionPlus,
    color,
  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  // ── 衬线展示档 ──────────────────────────────────────────────────────
  static TextStyle display(Color color) => _serif(sizeDisplay, color);
  static TextStyle displaySm(Color color) =>
      _serif(sizeDisplaySm, color, tracking: -0.012);
  static TextStyle displayXl(Color color, double viewportWidth) =>
      _serif(displayXlSize(viewportWidth), color, tracking: -0.028);

  /// `.sect-head h2`：24 衬线 /-.015em。
  ///
  /// 它不带 `.display` 类，行高沿用根上的 1.45；把 1.05 的展示档行高套过来
  /// 会让区块标题与副标题挤在一起。
  static TextStyle sectionTitle(Color color) =>
      _serif(sizeSection, color, height: 1.45, tracking: -0.015);
  static TextStyle statValue(Color color) => _serif(
    sizeStat,
    color,
    height: 1.15,
  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle readerStatValue(Color color) => _serif(
    sizeStatReader,
    color,
    height: 1.15,
  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle adminStatValue(Color color) => _serif(
    sizeStatAdmin,
    color,
    height: 1.15,
  ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  static TextStyle bigNum(Color color) =>
      _serif(sizeBigNum, color, height: 1, tracking: -0.03);
  static TextStyle brand(Color color) =>
      _serif(sizePanelTitle, color, weight: FontWeight.w500, tracking: -0.01);

  /// `.auth-card h2` / `.sp-mark h1` 都带 `.display` 类：衬线 + `line-height:1.05`。
  static TextStyle authTitle(Color color) => _serif(sizeAuthTitle, color);
  static TextStyle splashTitle(Color color) => _serif(sizeSplash, color);
  static TextStyle quote(Color color) =>
      _serif(sizeLarge, color, height: 1.55, style: FontStyle.italic);
  static TextStyle chapter(Color color) =>
      _serif(sizeTitle, color, height: 1.2);
}
