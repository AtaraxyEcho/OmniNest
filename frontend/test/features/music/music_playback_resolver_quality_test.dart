import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_local_preferences_controller.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_local_preference_store.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/application/music_playback_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

const OnlineTrack _onlineTrack = OnlineTrack(
  platform: 'netease',
  songId: '188888',
  title: 'Quality Song',
  artistName: 'Quality Artist',
);

void main() {
  test('resolver passes the preferred quality to online plans', () async {
    final api = _QualityRecordingApi();
    final resolver = MusicPlaybackResolver(
      api,
      preferredOnlineQuality: () => 'lossless',
    );

    await resolver.resolve(MusicPlayableItem.online(_onlineTrack));

    expect(api.onlineQualityRequests, ['lossless']);
  });

  test('resolver falls back to exhigh without a preference provider', () async {
    final api = _QualityRecordingApi();
    final resolver = MusicPlaybackResolver(api);

    await resolver.resolve(MusicPlayableItem.online(_onlineTrack));

    expect(api.onlineQualityRequests, ['exhigh']);
  });

  test('local preferences controller persists and reloads quality', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer.test(
      overrides: [
        musicLocalPreferenceStoreProvider.overrideWithValue(
          const MusicLocalPreferenceStore(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(
      musicLocalPreferencesControllerProvider.future,
    );
    expect(initial, 'exhigh');

    await container
        .read(musicLocalPreferencesControllerProvider.notifier)
        .setOnlineQuality('hires');
    expect(
      container.read(musicLocalPreferencesControllerProvider).asData?.value,
      'hires',
    );

    final reloaded = await SharedPreferences.getInstance();
    expect(reloaded.getString('music_online_quality'), 'hires');
  });
}

class _QualityRecordingApi implements MusicApi {
  final onlineQualityRequests = <String>[];

  @override
  Future<MusicPlaybackPlan> onlinePlaybackPlan(
    String platform,
    String songId, {
    String quality = 'exhigh',
  }) async {
    onlineQualityRequests.add(quality);
    return MusicPlaybackPlan(
      trackId: 'track-$songId',
      url: 'http://localhost/$songId.mp3',
      durationSeconds: 200,
      format: 'mp3',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
