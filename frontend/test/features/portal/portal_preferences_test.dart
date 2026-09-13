import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/portal/domain/portal_preferences.dart';

void main() {
  group('PortalPreferences', () {
    test('旧视觉偏好不再参与 Portal 状态', () {
      final preferences = PortalPreferences.fromJson(const <String, dynamic>{
        'visualFamily': 'atmosphericGallery',
        'desktopStyle': 'cinematicGallery',
        'weatherEffectsEnabled': true,
      });

      expect(preferences.toJson(), isNot(contains('visualFamily')));
      expect(preferences.toJson(), isNot(contains('desktopStyle')));
      expect(preferences.toJson(), isNot(contains('weatherEffectsEnabled')));
    });

    test('沉浸模式默认关闭并支持序列化', () {
      const preferences = PortalPreferences();
      expect(preferences.immersiveModeEnabled, isFalse);
      expect(
        preferences.copyWith(immersiveModeEnabled: true).toJson(),
        containsPair('immersiveModeEnabled', true),
      );
    });
  });

  group('PortalMusicVisualizerPreferences', () {
    test('默认使用单一视觉设置并开启播放器与音频条', () {
      const preferences = PortalMusicVisualizerPreferences();

      expect(preferences.visual.spectrum.lowResponse, 1.08);
      expect(preferences.visual.coverElements.originalCoverEnabled, isFalse);
      expect(preferences.visual.coverElements.borderEnabled, isFalse);
      expect(preferences.visual.coverElements.opacity, 1);
      expect(preferences.visual.coverElements.tiltDegrees, 0);
      expect(preferences.visual.player.enabled, isTrue);
      expect(preferences.visual.player.audioBarEnabled, isTrue);
      expect(preferences.toJson(), isNot(contains('selectedPresetId')));
      expect(preferences.toJson(), isNot(contains('customPresets')));
    });

    test('单一视觉设置支持序列化', () {
      final preferences = PortalMusicVisualizerPreferences(
        visual: PortalMusicVisualizerSettings.defaults.copyWith(
          coverElements: PortalCoverElementSettings.defaults.copyWith(
            opacity: 1,
            tiltDegrees: 7,
          ),
          player: PortalGlassPlayerSettings.defaults.copyWith(
            enabled: false,
            audioBarEnabled: false,
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
      expect(restored.visual.coverElements.opacity, 1);
      expect(restored.visual.coverElements.tiltDegrees, 7);
      expect(restored.visual.player.enabled, isFalse);
      expect(restored.visual.player.audioBarEnabled, isFalse);
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

      expect(restored.visual.spectrum.lowResponse, 1.4);
      expect(restored.visual.player.enabled, isFalse);
      expect(restored.visual.player.audioBarEnabled, isTrue);
    });

    test('旧视觉设置缺少 Hero 封面透明度时使用默认值', () {
      final restored = PortalMusicVisualizerPreferences.fromJson(
        const <String, dynamic>{
          'visual': <String, dynamic>{
            'coverElements': <String, dynamic>{'originalCoverEnabled': true},
          },
        },
      );

      expect(restored.visual.coverElements.originalCoverEnabled, isTrue);
      expect(restored.visual.coverElements.opacity, 1);
      expect(restored.visual.coverElements.tiltDegrees, 0);
    });

    test('封面倾斜角度读取时限制在编辑器范围内', () {
      final restored = PortalMusicVisualizerPreferences.fromJson(
        const <String, dynamic>{
          'visual': <String, dynamic>{
            'coverElements': <String, dynamic>{'tiltDegrees': 90},
          },
        },
      );

      expect(restored.visual.coverElements.tiltDegrees, 12);
    });
  });
}
