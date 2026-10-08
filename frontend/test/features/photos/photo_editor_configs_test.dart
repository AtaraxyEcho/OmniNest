import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations_en.dart';
import 'package:omninest/app/l10n/app_localizations_zh.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/features/photos/presentation/widgets/photo_editor_configs.dart';

void main() {
  test('编辑器配色跟环境暗色而不是 M3 默认色板', () {
    // 只给 ThemeData(brightness: dark) 会让主行动钮落到 M3 淡紫 primary，
    // 违反单强调色与 Zero Purple；这里钉住取自环境色板的四个关键色。
    final theme = photoEditorTheme(MobileEnvPalette.dark);
    expect(theme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, MobileEnvPalette.dark.accent);
    expect(theme.colorScheme.onPrimary, MobileEnvPalette.dark.onAccent);
    expect(theme.colorScheme.surface, MobileEnvPalette.dark.sheetSolid);
    expect(theme.scaffoldBackgroundColor, MobileEnvPalette.dark.stage);
    expect(
      buildPhotoEditorConfigs(
        AppLocalizationsZh(),
        MobileEnvPalette.dark,
      ).theme?.colorScheme.primary,
      MobileEnvPalette.dark.accent,
      reason: '配置必须真的带上这套配色',
    );
  });
  test('浅极性下编辑器翻到纸面而不是留在暗底', () {
    final theme = photoEditorTheme(MobileEnvPalette.light);
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.primary, MobileEnvPalette.light.accent);
    expect(theme.colorScheme.onPrimary, MobileEnvPalette.light.onAccent);
    expect(theme.colorScheme.surface, MobileEnvPalette.light.sheetSolid);
    expect(theme.scaffoldBackgroundColor, MobileEnvPalette.light.stage);
  });

  test('编辑器配置输出中文文案', () {
    final configs = buildPhotoEditorConfigs(
      AppLocalizationsZh(),
      MobileEnvPalette.dark,
    );
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
    final configs = buildPhotoEditorConfigs(
      AppLocalizationsEn(),
      MobileEnvPalette.dark,
    );
    expect(configs.i18n.cancel, 'Cancel');
    expect(configs.i18n.paintEditor.bottomNavigationBarText, 'Paint');
    expect(configs.cropRotateEditor.aspectRatios.first.text, 'Free');
  });
}
