import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/widgets/app_dropdown.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_preset_editor.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';
import 'package:omninest/features/music/presentation/player/music_visual_color_picker.dart';

/// 编辑视觉窗口的歌词分区：两种歌词形态二选一，且只展示所选形态的参数；
/// 溢光整体移除，颜色只保留已读/未读两项。
void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required bool lyricScrollMode,
    ValueChanged<bool>? onLyricScrollModeChanged,
  }) async {
    tester.view.physicalSize = const Size(520, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              height: 1000,
              child: MusicVisualEditorPanel(
                palette: MusicImmersivePalette.digital,
                source: PortalMusicVisualizerSettings.defaults,
                lyricScrollMode: lyricScrollMode,
                onLyricScrollModeChanged: onLyricScrollModeChanged,
                onChanged: (_) {},
                onSave: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('桌面组不再暴露歌词形态下拉：形态由布局决定', (tester) async {
    await pumpPanel(tester, lyricScrollMode: true);

    // 居中布局即多行歌词、两侧为滚动歌词，形态下拉已整体移除。
    expect(find.text('歌词显示模式'), findsNothing);
    // 多行歌词专属参数不出现。
    expect(find.text('可见行数'), findsNothing);
    expect(find.text('歌词呼吸效果'), findsNothing);
    // 两色与共用外观参数在两种形态下都可用。
    expect(find.text('在读歌词颜色'), findsOneWidget);
    expect(find.text('非当前句歌词颜色'), findsOneWidget);
    expect(find.text('歌词行距'), findsOneWidget);
    // 滑杆必须带具体数值与单位（默认值：字号 18px、行距 1.00×、透明度 50%）。
    expect(find.text('18 px'), findsOneWidget);
    // 行距与在读/未读字号缩放默认均为 1.00×，共三个滑杆。
    expect(find.text('1.00×'), findsNWidgets(3));
    expect(find.text('50%'), findsOneWidget);
    // 堆叠卡片开关在桌面组可见（默认开启）。
    expect(find.text('显示堆叠卡片'), findsOneWidget);
    // 在读/未读字号缩放滑杆（桌面组专属）。
    expect(find.text('在读歌词字号'), findsOneWidget);
    expect(find.text('未读歌词字号'), findsOneWidget);
  });

  testWidgets('多行歌词形态只显示多行歌词的参数', (tester) async {
    await pumpPanel(tester, lyricScrollMode: false);

    expect(find.text('可见行数'), findsOneWidget);
    expect(find.text('歌词呼吸效果'), findsOneWidget);
    expect(find.text('在读歌词颜色'), findsOneWidget);
    expect(find.text('非当前句歌词颜色'), findsOneWidget);
  });

  testWidgets('移动端组保留歌词形态切换并回写设备级偏好', (tester) async {
    bool? changed;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              height: 1000,
              child: MusicVisualEditorPanel(
                key: const ValueKey('mobile-mode-toggle'),
                palette: MusicImmersivePalette.digital,
                source: PortalMusicVisualizerSettings.defaults,
                lyricScrollMode: true,
                onLyricScrollModeChanged: (value) => changed = value,
                onChanged: (_) {},
                onSave: (_) {},
                onClose: () {},
                // 移动端宿主只注入移动端组：形态下拉由该组承载。
                sections: const <MusicVisualEditorSection>{
                  MusicVisualEditorSection.mobileLyrics,
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dropdown = find.byType(AppDropdown<PortalLyricLayoutMode>);
    expect(dropdown, findsOneWidget);
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('多行歌词').last);
    await tester.pumpAndSettle();

    expect(changed, isFalse);
  });

  testWidgets('歌词颜色只剩已读与未读两项，且不再提供溢光', (tester) async {
    await pumpPanel(tester, lyricScrollMode: true);

    expect(find.byType(MusicVisualPaintField), findsNWidgets(2));
    expect(find.text('当前歌词颜色'), findsNothing);
    expect(find.text('歌词溢光'), findsNothing);
    expect(find.text('溢光强度'), findsNothing);
    expect(find.text('溢光颜色'), findsNothing);
    expect(find.text('歌词渐变'), findsNothing);
  });

  testWidgets('关闭歌词开关后不再展示歌词参数', (tester) async {
    await pumpPanel(tester, lyricScrollMode: true);

    final lyricsSwitch = find.ancestor(
      of: find.text('歌词'),
      matching: find.byType(SwitchListTile),
    );
    expect(lyricsSwitch, findsOneWidget);
    await tester.ensureVisible(lyricsSwitch);
    await tester.pumpAndSettle();
    await tester.tap(lyricsSwitch);
    await tester.pumpAndSettle();

    expect(find.text('歌词显示模式'), findsNothing);
    expect(find.byType(MusicVisualPaintField), findsNothing);
  });

  testWidgets('译文开关两种形态共用并写回视觉设置', (tester) async {
    PortalMusicVisualizerSettings? draft;
    Future<void> pumpAndToggle({required bool scrollMode}) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 420,
                height: 1000,
                child: MusicVisualEditorPanel(
                  // 两种形态分别挂不同 key：pumpWidget 复用同型 Element 时
                  // 面板 State 会保留上一形态的草稿，必须强制重建。
                  key: ValueKey('translation-toggle-$scrollMode'),
                  palette: MusicImmersivePalette.digital,
                  source: PortalMusicVisualizerSettings.defaults,
                  lyricScrollMode: scrollMode,
                  onChanged: (next) => draft = next,
                  onSave: (_) {},
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final translationSwitch = find.ancestor(
        of: find.text('显示译文'),
        matching: find.byType(SwitchListTile),
      );
      expect(translationSwitch, findsOneWidget);
      await tester.ensureVisible(translationSwitch);
      await tester.pumpAndSettle();
      await tester.tap(translationSwitch);
      await tester.pumpAndSettle();
    }

    // 滚动歌词形态。
    await pumpAndToggle(scrollMode: true);
    expect(draft?.lyrics.translationEnabled, isFalse);
    draft = null;

    // 多行歌词形态。
    await pumpAndToggle(scrollMode: false);
    expect(draft?.lyrics.translationEnabled, isFalse);
  });

  testWidgets('逐字填充开关仅滚动形态展示并写回视觉设置', (tester) async {
    // 多行歌词形态没有逐字填充（填充仅作用于滚动列表）。
    await pumpPanel(tester, lyricScrollMode: false);
    expect(find.text('逐字填充'), findsNothing);

    // 滚动歌词形态展示开关，关闭后写回 wordFillEnabled: false。
    PortalMusicVisualizerSettings? draft;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              height: 1000,
              child: MusicVisualEditorPanel(
                key: const ValueKey('word-fill-toggle'),
                palette: MusicImmersivePalette.digital,
                source: PortalMusicVisualizerSettings.defaults,
                lyricScrollMode: true,
                onChanged: (next) => draft = next,
                onSave: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fillSwitch = find.ancestor(
      of: find.text('逐字填充'),
      matching: find.byType(SwitchListTile),
    );
    expect(fillSwitch, findsOneWidget);
    await tester.ensureVisible(fillSwitch);
    await tester.pumpAndSettle();
    await tester.tap(fillSwitch);
    await tester.pumpAndSettle();

    expect(draft?.lyrics.wordFillEnabled, isFalse);
  });
}
