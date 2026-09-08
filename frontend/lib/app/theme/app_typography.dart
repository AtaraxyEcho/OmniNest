import 'package:flutter/material.dart';

/// 全局排版 token。
///
/// 字号常量以 Photos 阶梯为基准定稿（11 值、三族：caption/body/title/
/// display），是业务字号与 Material `textTheme` 的唯一来源；内容语义
/// （时间戳、eyebrow 等）由业务组件表达，不进入字号命名。
abstract final class AppTypography {
  /// 全局西文字体。中文字符经 [fontFamilyFallback] 回落至中文字体渲染。
  static const String fontFamily = 'Inter';

  /// 全局字形回落链，承接西文字体缺失的中文与 CJK 标点。
  static const List<String> fontFamilyFallback = <String>['NotoSansSC'];

  /// 等宽场景（代码、链接、路径）统一使用的字体。
  static const String monoFamily = 'JetBrainsMono';

  /// 等宽字体回落链：代码中的中文回落中文字体，其余回落平台等宽字体。
  static const List<String> monoFamilyFallback = <String>[
    'NotoSansSC',
    'monospace',
  ];

  /// 衬线展示字体（模块页头、Hero 标题），中文回落 Noto Serif SC。
  static const String serifFamily = 'InstrumentSerif';

  /// 衬线展示字体的中文回落链。
  static const List<String> serifFamilyFallback = <String>['NotoSerifSC'];

  // ── 字号语义 token（勿在业务代码写裸数字字号）──────────────────────

  /// Portal Hero 等巨字。
  static const double displayLarge = 48;

  /// 预留展示档。
  static const double displayMedium = 45;

  /// 特大页头。
  static const double displaySmall = 36;

  /// 模块页头（衬线伴生档）。
  static const double headlineLarge = 32;

  /// 区块页头 / 指标值。
  static const double headlineMedium = 28;

  /// 卡片区头 / 空态大字。
  static const double headlineSmall = 24;

  /// 面板 / 弹窗标题。
  static const double titleLarge = 20;

  /// 列表 / 卡片强调标题。
  static const double titleMedium = 16;

  /// 次级标题 / 小节标题。
  static const double titleSmall = 14;

  /// 列表项标题 / 正文。
  static const double bodyLarge = 14;

  /// 密集正文默认。
  static const double bodyMedium = 13;

  /// 副标题 / 描述。
  static const double bodySmall = 12;

  /// eyebrow / 时间戳等辅助文字。
  static const double labelSmall = 11;

  /// 按钮等强调标签。
  static const double labelLarge = 14;

  /// 中等标签。
  static const double labelMedium = 12;

  /// 根据系统文字缩放设置缩放字号，确保可访问性。
  /// [base] 为设计稿字号，[context] 用于读取 MediaQuery.textScaler。
  static double scaled(BuildContext context, double base) {
    return MediaQuery.textScalerOf(context).scale(base);
  }

  /// 返回应用了系统缩放的 TextStyle 副本。
  static TextStyle scaledStyle(BuildContext context, TextStyle base) {
    return base.copyWith(fontSize: scaled(context, base.fontSize ?? 14));
  }
}
