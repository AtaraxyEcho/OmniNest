import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/preferences/preference_snapshot.dart';
import 'package:omninest/core/preferences/user_preferences_api.dart';
import 'package:omninest/features/music/application/music_visualizer_preset_controller.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('旧远端视觉作用域自动迁移为单一设置', () async {
    final api =
        _FakeUserPreferencesApi()
          ..values['portal.music_visualizer'] = const <String, dynamic>{
            'selectedPresetId': 'custom_demo',
            'customPresets': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'custom_demo',
                'player': <String, dynamic>{'enabled': false},
              },
            ],
          };
    final container = ProviderContainer.test(
      overrides: [
        userPreferencesApiProvider.overrideWithValue(api),
        authSessionProvider.overrideWith(_AuthenticatedSessionNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final preferences = await container.read(
      musicVisualizerPreferencesProvider.future,
    );

    expect(preferences.visual.player.enabled, isFalse);
    expect(
      api.updates['music.player.visual.v1'],
      containsPair(
        'schemaVersion',
        PortalMusicVisualizerPreferences.currentSchemaVersion,
      ),
    );
    expect(api.deletedScopes, contains('portal.music_visualizer'));
    expect(api.values.containsKey('portal.music_visualizer'), isFalse);
  });

  test('旧远端视觉作用域删除失败时迁移结果仍可用并在恢复后重放', () async {
    final api =
        _FakeUserPreferencesApi()
          ..values['portal.music_visualizer'] = const <String, dynamic>{
            'selectedPresetId': 'custom_demo',
            'customPresets': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'custom_demo',
                'player': <String, dynamic>{'enabled': false},
              },
            ],
          }
          ..failNextDelete = true;
    final container = ProviderContainer.test(
      overrides: [
        userPreferencesApiProvider.overrideWithValue(api),
        authSessionProvider.overrideWith(_AuthenticatedSessionNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final preferences = await container.read(
      musicVisualizerPreferencesProvider.future,
    );

    expect(preferences.visual.player.enabled, isFalse);
    expect(api.values.containsKey('portal.music_visualizer'), isTrue);

    await container
        .read(preferenceSyncServiceProvider)
        .load(userId: 'user-1', scope: 'portal.music_visualizer');
    expect(api.values.containsKey('portal.music_visualizer'), isFalse);
    expect(api.deletedScopes, contains('portal.music_visualizer'));
  });

  test('旧本地键自动迁移且支持恢复默认设置', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'portal_music_visualizer_preferences': jsonEncode(const <String, dynamic>{
        'selectedPresetId': 'custom-test',
        'customPresets': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'custom-test',
            'player': <String, dynamic>{'enabled': false},
          },
        ],
      }),
    });
    final api = _FakeUserPreferencesApi();
    final container = ProviderContainer.test(
      overrides: [
        userPreferencesApiProvider.overrideWithValue(api),
        authSessionProvider.overrideWith(_AuthenticatedSessionNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final migrated = await container.read(
      musicVisualizerPreferencesProvider.future,
    );
    expect(migrated.visual.player.enabled, isFalse);

    await container
        .read(musicVisualizerPreferencesProvider.notifier)
        .restoreDefaults();
    final restored = container.read(musicVisualizerPreferencesProvider).value!;
    expect(restored.visual.player.enabled, isTrue);
  });

  test('保存视觉设置同步到本地和远端', () async {
    final api = _FakeUserPreferencesApi();
    final container = ProviderContainer.test(
      overrides: [
        userPreferencesApiProvider.overrideWithValue(api),
        authSessionProvider.overrideWith(_AuthenticatedSessionNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicVisualizerPreferencesProvider.future);

    final visual = PortalMusicVisualizerSettings.defaults.copyWith(
      player: PortalGlassPlayerSettings.defaults.copyWith(enabled: false),
    );
    await container
        .read(musicVisualizerPreferencesProvider.notifier)
        .saveVisual(visual);

    expect(
      container
          .read(musicVisualizerPreferencesProvider)
          .value!
          .visual
          .player
          .enabled,
      isFalse,
    );
    expect(api.updates['music.player.visual.v1']?['visual'], isA<Map>());
  });

  test('歌词与播放器视觉参数可完整序列化', () {
    final preferences = PortalMusicVisualizerPreferences(
      visual: PortalMusicVisualizerSettings.defaults.copyWith(
        lyrics: PortalLyricVisualSettings.defaults.copyWith(
          visibleLines: 7,
          lineSpacing: 1.4,
          fontSizePx: 20,
          currentFontSizePx: 36,
          currentPaint: const LyricPaint.vertical(0xFFB7FFE7, 0xFF7098A0),
          inactivePaint: const LyricPaint.solid(0xFFFFFFFF),
          breathingEnabled: false,
          layout: PortalMusicLayout.right,
        ),
        player: PortalGlassPlayerSettings.defaults.copyWith(
          volumeEnabled: false,
        ),
      ),
    );

    final restored = PortalMusicVisualizerPreferences.fromJson(
      preferences.toJson(),
    );

    expect(restored.schemaVersion, 16);
    expect(restored.visual.lyrics.visibleLines, 7);
    expect(restored.visual.lyrics.lineSpacing, 1.4);
    expect(
      restored.visual.lyrics.currentPaint.mode,
      LyricPaintMode.verticalGradient,
    );
    expect(restored.visual.lyrics.currentPaint.colors, <int>[
      0xFFB7FFE7,
      0xFF7098A0,
    ]);
    expect(restored.visual.lyrics.inactivePaint.mode, LyricPaintMode.solid);
    expect(restored.visual.lyrics.inactivePaint.primary, 0xFFFFFFFF);
    expect(restored.visual.lyrics.breathingEnabled, isFalse);
    expect(restored.visual.lyrics.layout, PortalMusicLayout.right);
    expect(restored.visual.player.volumeEnabled, isFalse);
  });

  test('旧歌词颜色迁移到当前设置结构并丢弃音频条字段', () {
    final restored = PortalMusicVisualizerPreferences.fromJson(
      const <String, dynamic>{
        'schemaVersion': 4,
        'visual': <String, dynamic>{
          'lyrics': <String, dynamic>{
            'textColorValue': 0xFFAABBCC,
            'showAllLines': true,
          },
          'player': <String, dynamic>{'audioBarStyle': 'mirroredWave'},
        },
      },
    );

    expect(restored.schemaVersion, 16);
    expect(restored.visual.lyrics.currentPaint.primary, 0xFFAABBCC);
    expect(
      restored.visual.lyrics.inactivePaint.primary,
      PortalLyricVisualSettings.defaults.inactivePaint.primary,
    );
    // 音频条已整体移除：旧字段被静默忽略，播放器退回默认设置。
    expect(restored.visual.player.volumeEnabled, isTrue);
    expect(restored.visual.player.progressEnabled, isTrue);
  });

  test('桌面歌词字号以 px 保存，旧倍率按当时布局基准换算', () {
    final legacy = PortalLyricVisualSettings.fromJson(const <String, dynamic>{
      'layout': 'left',
      'activeFontScale': 1.5,
      'inactiveFontScale': 0.75,
    });
    // 两侧布局基准 44/18：1.5 倍越界夹到上限 64，0.75 倍取整为 14。
    expect(legacy.activeFontSizePx, 64);
    expect(legacy.inactiveFontSizePx, 14);
    // 倍率字段退出契约：只回写 px。
    expect(legacy.toJson().containsKey('activeFontScale'), isFalse);
    expect(legacy.toJson()['activeFontSizePx'], 64);

    // 居中布局基准不同，同一倍率换算出另一组 px。
    expect(
      PortalLyricVisualSettings.fromJson(const <String, dynamic>{
        'layout': 'center',
        'activeFontScale': 1.5,
      }).activeFontSizePx,
      27,
    );

    // 未调过字号时不写 px，由布局样例基准兜底。
    expect(PortalLyricVisualSettings.defaults.activeFontSizePx, isNull);
    expect(PortalLyricVisualSettings.fromJson(null).inactiveFontSizePx, isNull);
    expect(
      PortalLyricVisualSettings.defaults.toJson().containsKey('fontSizePx'),
      isTrue,
    );
  });

  test('v11 旧设置中的频响与封面元素字段被静默丢弃', () {
    final restored = PortalMusicVisualizerPreferences.fromJson(
      const <String, dynamic>{
        'schemaVersion': 11,
        'visual': <String, dynamic>{
          'spectrum': <String, dynamic>{'lowResponse': 1.5},
          'coverElements': <String, dynamic>{'originalCoverEnabled': true},
          'lyrics': <String, dynamic>{'translationEnabled': false},
          'player': <String, dynamic>{'enabled': false},
        },
      },
    );

    expect(restored.schemaVersion, 16);
    // 频响与封面元素（含原始封面）已整体移除：字段不再存在，载入不报错；
    // deckEnabled 为 v13 新增的堆叠卡片开关。
    expect(restored.visual.lyrics.translationEnabled, isFalse);
    expect(restored.visual.player.enabled, isFalse);
    expect(restored.toJson()['visual'].keys, <String>[
      'lyrics',
      'player',
      'deckEnabled',
    ]);
  });

  test('桌面布局预设按编辑器展示顺序排列：居左（默认）、居中、居右', () {
    expect(PortalMusicLayout.values, <PortalMusicLayout>[
      PortalMusicLayout.left,
      PortalMusicLayout.center,
      PortalMusicLayout.right,
    ]);
    expect(PortalLyricVisualSettings.defaults.layout, PortalMusicLayout.left);
  });
}

class _AuthenticatedSessionNotifier extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async {
    return AuthSessionState(
      user: UserProfile(id: 'user-1', username: 'tester', role: 'MEMBER'),
    );
  }
}

class _FakeUserPreferencesApi extends UserPreferencesApi {
  _FakeUserPreferencesApi()
    : super(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
      );

  final Map<String, Map<String, dynamic>> values =
      <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> updates =
      <String, Map<String, dynamic>>{};
  final Map<String, int> versions = <String, int>{};
  final List<String> deletedScopes = <String>[];
  bool failNextDelete = false;

  @override
  Future<PreferenceSnapshot> getSnapshot(String scope) async {
    return PreferenceSnapshot(
      scope: scope,
      preferences: values[scope] ?? const <String, dynamic>{},
      version: values.containsKey(scope) ? (versions[scope] ?? 0) : null,
    );
  }

  @override
  Future<PreferenceSnapshot> patch({
    required String scope,
    required int? baseVersion,
    required Map<String, dynamic> changes,
    Set<String> removeKeys = const <String>{},
  }) async {
    final preferences = Map<String, dynamic>.from(
      values[scope] ?? const <String, dynamic>{},
    )..addAll(changes);
    for (final key in removeKeys) {
      preferences.remove(key);
    }
    values[scope] = preferences;
    updates[scope] = Map<String, dynamic>.from(changes);
    versions[scope] = (versions[scope] ?? -1) + 1;
    return PreferenceSnapshot(
      scope: scope,
      preferences: preferences,
      version: versions[scope],
    );
  }

  @override
  Future<void> delete({required String scope, required int baseVersion}) async {
    if (failNextDelete) {
      failNextDelete = false;
      throw const AppException(code: 'OFFLINE', message: 'offline');
    }
    deletedScopes.add(scope);
    values.remove(scope);
    versions.remove(scope);
  }
}
