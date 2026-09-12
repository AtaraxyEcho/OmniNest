import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_media_session.dart';

void main() {
  test('媒体键命令按切换与单向下发语义转接到回调', () async {
    var toggleCalls = 0;
    var playCalls = 0;
    var pauseCalls = 0;
    var nextCalls = 0;
    var previousCalls = 0;
    MusicMediaKeyBridge.register(
      MusicMediaCommandCallbacks(
        onPlay: () async => playCalls++,
        onPause: () async => pauseCalls++,
        onNext: () async => nextCalls++,
        onPrevious: () async => previousCalls++,
        onPlayPauseToggle: () async => toggleCalls++,
      ),
    );

    await MusicMediaKeyBridge.dispatchPlayPauseToggle();
    await MusicMediaKeyBridge.dispatch(play: true);
    await MusicMediaKeyBridge.dispatch(play: false, pause: true);
    await MusicMediaKeyBridge.dispatch(play: false, next: true);
    await MusicMediaKeyBridge.dispatch(play: false, previous: true);

    expect(toggleCalls, 1);
    expect(playCalls, 1);
    expect(pauseCalls, 1);
    expect(nextCalls, 1);
    expect(previousCalls, 1);
  });
}
