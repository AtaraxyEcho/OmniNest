import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/music_portal.dart';

void main() {
  group('PortalMusicVisualizerPreferences', () {
    test('默认使用单一视觉设置并开启播放器', () {
      const preferences = PortalMusicVisualizerPreferences();

      expect(preferences.visual.player.enabled, isTrue);
      // 桌面播放详情页默认布局居左（用户确认的默认构图）。
      expect(preferences.visual.lyrics.layout, PortalMusicLayout.left);
      expect(preferences.toJson(), isNot(contains('selectedPresetId')));
      expect(preferences.toJson(), isNot(contains('customPresets')));
    });

    test('单一视觉设置支持序列化', () {
      final preferences = PortalMusicVisualizerPreferences(
        visual: PortalMusicVisualizerSettings.defaults.copyWith(
          player: PortalGlassPlayerSettings.defaults.copyWith(enabled: false),
          lyrics: PortalLyricVisualSettings.defaults.copyWith(
            layout: PortalMusicLayout.right,
          ),
        ),
      );

      final restored = PortalMusicVisualizerPreferences.fromJson(
        preferences.toJson(),
      );

      expect(
        restored.schemaVersion,
        PortalMusicVisualizerPreferences.currentSchemaVersion,
      );
      expect(restored.visual.player.enabled, isFalse);
      expect(restored.visual.lyrics.layout, PortalMusicLayout.right);
    });

    test('旧自定义预设迁移为单一视觉设置', () {
      final restored = PortalMusicVisualizerPreferences.fromJson(
        const <String, dynamic>{
          'selectedPresetId': 'custom_demo',
          'customPresets': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'custom_demo',
              'spectrum': <String, dynamic>{'lowResponse': 1.4},
              'player': <String, dynamic>{'enabled': false},
            },
          ],
        },
      );

      // 频响已整体移除：旧键静默丢弃，播放器开关照常迁移。
      expect(restored.visual.player.enabled, isFalse);
      expect(restored.visual.lyrics.layout, PortalMusicLayout.left);
    });

    test('旧歌词位置按镜像迁移到桌面布局', () {
      final mirrored = PortalMusicVisualizerPreferences.fromJson(
        const <String, dynamic>{
          'visual': <String, dynamic>{
            'lyrics': <String, dynamic>{'position': 'left'},
          },
        },
      );
      final centered = PortalMusicVisualizerPreferences.fromJson(
        const <String, dynamic>{
          'visual': <String, dynamic>{
            'lyrics': <String, dynamic>{'position': 'center'},
          },
        },
      );

      // 旧"歌词居左"= 卡组居右，与旧语义互为镜像。
      expect(mirrored.visual.lyrics.layout, PortalMusicLayout.right);
      expect(centered.visual.lyrics.layout, PortalMusicLayout.center);
    });

    test('旧设置中的频响与封面元素字段被静默丢弃', () {
      final restored = PortalMusicVisualizerPreferences.fromJson(
        const <String, dynamic>{
          'visual': <String, dynamic>{
            'spectrum': <String, dynamic>{'lowResponse': 1.5},
            'coverElements': <String, dynamic>{'originalCoverEnabled': true},
          },
        },
      );

      // 封面元素（含原始封面）与频响已整体移除：字段不再存在，载入不报错。
      expect(restored.toJson()['visual'].keys, <String>[
        'lyrics',
        'player',
        'deckEnabled',
      ]);
    });
  });
}
