import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_deck_source_selection_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

void main() {
  test('音乐来源筛选同步新增与断开的外部平台', () async {
    late _FakePlatformLibraryController platformController;
    final container = ProviderContainer.test(
      overrides: [
        musicPlatformLibraryProvider.overrideWith(() {
          platformController = _FakePlatformLibraryController(
            const MusicPlatformLibraryState(
              statuses: [
                MusicPlatformStatus(
                  platform: 'netease',
                  displayName: 'NetEase Cloud Music',
                  enabled: true,
                  connected: true,
                  capabilities: MusicPlatformCapabilities(),
                ),
              ],
            ),
          );
          return platformController;
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(musicPlatformLibraryProvider.future);
    expect(container.read(musicDeckSourceSelectionProvider), {
      MusicPlatform.local,
      MusicPlatform.netease,
    });

    container
        .read(musicDeckSourceSelectionProvider.notifier)
        .toggle(MusicPlatform.local);
    platformController.replace(
      const MusicPlatformLibraryState(
        statuses: [
          MusicPlatformStatus(
            platform: 'netease',
            displayName: 'Netease Music',
            enabled: true,
            connected: true,
            capabilities: MusicPlatformCapabilities(),
          ),
        ],
      ),
    );

    expect(container.read(musicDeckSourceSelectionProvider), {
      MusicPlatform.netease,
    });
  });
}

class _FakePlatformLibraryController extends MusicPlatformLibraryController {
  _FakePlatformLibraryController(this.initialState);

  final MusicPlatformLibraryState initialState;

  @override
  Future<MusicPlatformLibraryState> build() async => initialState;

  void replace(MusicPlatformLibraryState next) {
    state = AsyncData(next);
  }
}
