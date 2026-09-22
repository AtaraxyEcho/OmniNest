import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('封面元素渲染管线（含原始封面）已整体删除', () {
    final stageSource =
        File(
          'lib/features/music/presentation/player/music_immersive_player_stage.dart',
        ).readAsStringSync();
    final playerSource =
        File(
          'lib/features/music/presentation/player/music_immersive_player.dart',
        ).readAsStringSync();

    // 渲染文件已删除，舞台与播放器不再有封面底板与频谱接线。
    expect(
      File(
        'lib/features/music/presentation/player/music_immersive_cover_plane.dart',
      ).existsSync(),
      isFalse,
    );
    expect(stageSource, isNot(contains('_DigitalImmersiveCoverPlane')));
    expect(stageSource, isNot(contains('coverElements')));
    expect(stageSource, isNot(contains('spectrumFeed')));
    expect(playerSource, isNot(contains('music_immersive_cover_plane')));
    expect(playerSource, isNot(contains('musicSpectrumFeedProvider')));
  });

  test('视觉设置模型不再包含频响与封面元素字段', () {
    final modelSource =
        File(
          'lib/features/music/domain/music_visualizer_preset.dart',
        ).readAsStringSync();
    final editorSource =
        File(
          'lib/features/music/presentation/player/music_immersive_preset_editor.dart',
        ).readAsStringSync();

    expect(modelSource, isNot(contains('PortalSpectrumVisualSettings')));
    expect(modelSource, isNot(contains('PortalCoverElementSettings')));
    expect(modelSource, isNot(contains("json?['coverElements']")));
    expect(modelSource, contains('static const int currentSchemaVersion = 15'));
    // 编辑面板不再有封面与频响分区。
    expect(editorSource, isNot(contains('MusicVisualEditorSection.cover')));
    expect(editorSource, isNot(contains('MusicVisualEditorSection.spectrum')));
    expect(editorSource, isNot(contains('_draft.coverElements')));
    expect(editorSource, isNot(contains('_draft.spectrum')));
    // 音频条整体移除：模型不再保留样式枚举，面板不再有音频条文案。
    expect(modelSource, isNot(contains('MusicAudioBarStyle')));
    expect(editorSource, isNot(contains('musicVisualizerAudioBar')));
  });

  test('桌面沉浸面板只注入桌面分组且不再有无效分区引用', () {
    final stageSource =
        File(
          'lib/features/music/presentation/player/music_immersive_player_stage.dart',
        ).readAsStringSync();
    final mobileSource =
        File(
          'lib/features/music/presentation/player/music_mobile_now_playing.dart',
        ).readAsStringSync();

    expect(stageSource, contains('MusicVisualEditorSection.desktop'));
    expect(
      stageSource,
      isNot(contains('MusicVisualEditorSection.mobileLyrics')),
    );
    expect(mobileSource, contains('MusicVisualEditorSection.mobileLyrics'));
  });

  test('Portal 沉浸模式为顶部栏预留视觉编辑空间', () {
    final portalSource =
        File(
          'lib/features/portal/presentation/widgets/portal_desktop_visual_shells.dart',
        ).readAsStringSync();
    final stageSource =
        File(
          'lib/features/music/presentation/player/music_immersive_player_stage.dart',
        ).readAsStringSync();

    expect(portalSource, contains('reservedTopInset:'));
    expect(portalSource, contains('MediaQuery.paddingOf(context).top + 58'));
    expect(stageSource, contains('widget.reservedTopInset + 12 * scale'));
  });

  test('视觉编辑器切换选项时保留滚动位置', () {
    final editorSource =
        File(
          'lib/features/music/presentation/player/music_immersive_preset_editor.dart',
        ).readAsStringSync();
    final stageSource =
        File(
          'lib/features/music/presentation/player/music_immersive_player_stage.dart',
        ).readAsStringSync();

    expect(
      editorSource,
      contains('late final ScrollController _scrollController'),
    );
    expect(editorSource, contains('controller: _scrollController'));
    expect(editorSource, contains('_scrollController.dispose()'));
    expect(stageSource, contains("ValueKey('music-visual-editor-positioned')"));
    expect(stageSource, contains("ValueKey('music-visual-editor')"));
  });
}
