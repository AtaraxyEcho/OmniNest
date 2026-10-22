import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_behavior.dart';
import 'package:omninest/features/video/presentation/widgets/subtitle_parser.dart';

void main() {
  group('播放器行为', () {
    test('时长按控制栏格式输出', () {
      expect(formatMoviePlayerDuration(const Duration(seconds: 65)), '01:05');
      expect(
        formatMoviePlayerDuration(
          const Duration(hours: 2, minutes: 3, seconds: 4),
        ),
        '2:03:04',
      );
    });

    test('流式 Seek 限制负值和超出时长的目标', () {
      expect(clampMovieSeekSeconds(const Duration(seconds: -10), 0), 0);
      expect(clampMovieSeekSeconds(const Duration(seconds: 90), 60), 60);
      expect(clampMovieSeekSeconds(const Duration(seconds: 30), 60), 30);
    });

    test('播放完成使用片尾二十秒窗口', () {
      expect(isMoviePlaybackCompleted(79, 100), isFalse);
      expect(isMoviePlaybackCompleted(80, 100), isTrue);
      expect(isMoviePlaybackCompleted(100, 0), isFalse);
    });

    test('续播进度在片尾 95% 以上归零且切集不继承主条目进度', () {
      expect(
        resolveMovieResumeSeconds(
          isMainItem: true,
          positionSeconds: 600,
          durationSeconds: 3600,
        ),
        600,
      );
      expect(
        resolveMovieResumeSeconds(
          isMainItem: true,
          positionSeconds: 3500,
          durationSeconds: 3600,
        ),
        0,
      );
      expect(
        resolveMovieResumeSeconds(
          isMainItem: false,
          positionSeconds: 600,
          durationSeconds: 3600,
        ),
        0,
      );
    });

    test('字幕命中保持最后一个重叠提示', () {
      const cues = <SubtitleCue>[
        SubtitleCue(startMs: 1000, endMs: 3000, text: 'first'),
        SubtitleCue(startMs: 2000, endMs: 4000, text: 'second'),
      ];

      expect(
        findActiveSubtitleCueIndex(cues, const Duration(milliseconds: 2500)),
        1,
      );
      expect(
        findActiveSubtitleCueIndex(cues, const Duration(milliseconds: 5000)),
        -1,
      );
    });

    test('常用快捷键映射保持平台边界', () {
      expect(
        resolveMoviePlayerKeyboardAction(
          LogicalKeyboardKey.keyK,
          shiftPressed: false,
          isWeb: false,
        ),
        MoviePlayerKeyboardAction.playPause,
      );
      expect(
        resolveMoviePlayerKeyboardAction(
          LogicalKeyboardKey.keyN,
          shiftPressed: true,
          isWeb: false,
        ),
        MoviePlayerKeyboardAction.nextEpisode,
      );
      expect(
        resolveMoviePlayerKeyboardAction(
          LogicalKeyboardKey.f11,
          shiftPressed: false,
          isWeb: true,
        ),
        isNull,
      );
    });

    test('播放切换命令在冷却时间内只接受一次', () {
      final gate = MoviePlayerCommandGate();
      final start = DateTime(2026, 7, 30, 12);

      expect(gate.accept(start), isTrue);
      expect(
        gate.accept(start.add(const Duration(milliseconds: 100))),
        isFalse,
      );
      expect(gate.accept(start.add(const Duration(milliseconds: 260))), isTrue);
    });
  });
}
