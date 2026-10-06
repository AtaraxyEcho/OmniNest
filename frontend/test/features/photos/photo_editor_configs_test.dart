import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations_en.dart';
import 'package:omninest/app/l10n/app_localizations_zh.dart';
import 'package:omninest/app/theme/mobile_env_colors.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_editor_configs.dart';

void main() {
  test('编辑器配色跟环境暗色而不是 M3 默认色板', () {
    // 只给 ThemeData(brightness: dark) 会让主行动钮落到 M3 淡紫 primary，
    // 违反单强调色与 Zero Purple；这里钉住取自环境色板的四个关键色。
    final theme = photoEditorTheme();
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, MobileEnvColors.accent);
    expect(theme.colorScheme.onPrimary, MobileEnvColors.onAccent);
    expect(theme.colorScheme.surface, MobileEnvColors.sheetSolid);
    expect(theme.scaffoldBackgroundColor, MobileEnvColors.stage);
    expect(
      buildPhotoEditorConfigs(AppLocalizationsZh()).theme?.colorScheme.primary,
      MobileEnvColors.accent,
      reason: '配置必须真的带上这套配色',
    );
  });
  test('编辑器配置输出中文文案', () {
    final configs = buildPhotoEditorConfigs(AppLocalizationsZh());
    expect(configs.i18n.cancel, '取消');
    expect(configs.i18n.done, '完成');
    expect(configs.i18n.paintEditor.bottomNavigationBarText, '绘画');
    expect(configs.i18n.textEditor.bottomNavigationBarText, '文字');
    expect(configs.i18n.cropRotateEditor.bottomNavigationBarText, '裁剪旋转');
    expect(configs.i18n.tuneEditor.brightness, '亮度');
    expect(configs.i18n.filterEditor.bottomNavigationBarText, '滤镜');
    expect(configs.i18n.filterEditor.filters.none, '无滤镜');
    expect(configs.cropRotateEditor.aspectRatios.first.text, '自由');
    expect(configs.cropRotateEditor.aspectRatios[1].text, '原始');
  });

  test('编辑器配置输出英文文案', () {
    final configs = buildPhotoEditorConfigs(AppLocalizationsEn());
    expect(configs.i18n.cancel, 'Cancel');
    expect(configs.i18n.paintEditor.bottomNavigationBarText, 'Paint');
    expect(configs.cropRotateEditor.aspectRatios.first.text, 'Free');
  });
}
