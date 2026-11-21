part of 'music_models.dart';

class MusicLyricWord {
  const MusicLyricWord({
    required this.offset,
    required this.duration,
    required this.text,
  });

  /// 相对所在行起始位置的偏移；行首早于锚点时可为负值（见 `_nearestWords`）。
  final Duration offset;
  final Duration duration;
  final String text;

  Duration get end => offset + duration;

  /// 是否为空白词元：`yrc` 常用一个长时长的空白词元承载句后的静默与间奏，
  /// 它不是演唱时长。
  bool get isBlank => text.trim().isEmpty;
}

class MusicLyricLine {
  const MusicLyricLine({
    required this.position,
    required this.text,
    this.translation,
    this.words = const <MusicLyricWord>[],
  });

  final Duration position;
  final String text;

  /// 译文行（按时间戳就近对齐或同时间戳双行 LRC 自动合并）。
  final String? translation;

  /// 词级时间轴：为空表示只有行级时间戳（本地 LRC 或平台未返回逐字数据）。
  ///
  /// 词级数据缺失时渲染层按 [estimatedVocalSpan] 平滑降级填充，唱完即停满格。
  final List<MusicLyricWord> words;

  bool get hasTranslation =>
      translation != null && translation!.trim().isNotEmpty;

  bool get hasWords => words.isNotEmpty;

  /// 词级数据的结束时间（相对行首）；无词级数据时为 null。
  Duration? get wordsEnd => words.isEmpty ? null : words.last.end;

  /// 最后一个非空白词元的结束时间（相对行首）：歌手唱完本句的时刻。
  /// 全是空白词元（句后静默）时为 null。
  Duration? get vocalEnd {
    Duration? end;
    for (final word in words) {
      if (word.isBlank) {
        continue;
      }
      final wordEnd = word.end;
      if (end == null || wordEnd > end) {
        end = wordEnd;
      }
    }
    return end;
  }

  /// 行内时间 [withinLine] 对应的逐字填充比例（0..1）＝已完成词时长 / 总演唱时长。
  ///
  /// 无词级数据或总演唱时长为 0 时返回 null；渲染层在 null 时按 [span] 封顶的
  /// 估算演唱时长填充（见 [estimatedVocalSpan]），唱完即停在满格。
  double? fillProgressAt(Duration withinLine) =>
      fillStateAt(withinLine)?.fraction;

  /// 统一进度计算：有逐字数据时按词元真实 `offset/duration` 精确推进，
  /// 无逐字数据时自动复用 [estimatedVocalSpan] 平滑降级。
  double progressAt(Duration withinLine, {required Duration lineSpan}) {
    if (withinLine <= Duration.zero) {
      return 0.0;
    }
    final wordProgress = fillProgressAt(withinLine);
    if (wordProgress != null) {
      return wordProgress;
    }
    final vocalSpan = estimatedVocalSpan(lineSpan);
    if (vocalSpan <= Duration.zero) {
      return 1.0;
    }
    return (withinLine.inMilliseconds / vocalSpan.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  /// 行内时间 [withinLine] 处的填充进度，以及补间可以安全推进到的下一个目标。
  ({double fraction, double nextFraction, Duration toNextFraction})?
  fillStateAt(Duration withinLine) {
    if (words.isEmpty) {
      return null;
    }
    var totalMs = 0;
    for (final word in words) {
      if (word.isBlank) {
        continue;
      }
      totalMs += word.duration.inMilliseconds;
    }
    if (totalMs <= 0) {
      return null;
    }
    double ratio(int completedMs) =>
        (completedMs / totalMs).clamp(0.0, 1.0).toDouble();
    var completedMs = 0;
    for (final word in words) {
      if (word.isBlank) {
        continue;
      }
      final end = word.offset + word.duration;
      if (withinLine < word.offset) {
        final current = ratio(completedMs);
        return (
          fraction: current,
          nextFraction: current,
          toNextFraction: word.offset - withinLine,
        );
      }
      final beforeMs = completedMs;
      if (withinLine < end) {
        completedMs += (withinLine - word.offset).inMilliseconds;
        return (
          fraction: ratio(completedMs),
          nextFraction: ratio(beforeMs + word.duration.inMilliseconds),
          toNextFraction: end - withinLine,
        );
      }
      completedMs = beforeMs + word.duration.inMilliseconds;
    }
    return (fraction: 1.0, nextFraction: 1.0, toNextFraction: Duration.zero);
  }

  /// 无词级时间轴时的演唱时长估算：字符数 × 平均语速（300ms），最低 1200ms，
  /// 并以 [span]（本行与下一行的间隙）封顶。唱完即停在满格，不拖慢间奏。
  Duration estimatedVocalSpan(Duration span) {
    const msPerCharacter = 300;
    const minMs = 1200;
    final spanMs = span.inMilliseconds;
    if (spanMs <= 0) {
      return Duration.zero;
    }
    var ms = text.runes.length * msPerCharacter;
    if (ms < minMs) {
      ms = minMs;
    }
    if (ms > spanMs) {
      ms = spanMs;
    }
    return Duration(milliseconds: ms);
  }

  MusicLyricLine copyWith({
    Duration? position,
    String? text,
    String? translation,
    List<MusicLyricWord>? words,
  }) {
    return MusicLyricLine(
      position: position ?? this.position,
      text: text ?? this.text,
      translation: translation ?? this.translation,
      words: words ?? this.words,
    );
  }
}

class MusicPlatformLyrics {
  const MusicPlatformLyrics({
    required this.lyrics,
    this.translation,
    this.words,
  });

  final String lyrics;
  final String? translation;

  /// 逐字歌词原始载荷（网易云 `yrc` / `elrc` / `krc`），平台不提供时为 null。
  final String? words;
}

/// Lrclib 歌词搜索候选结果。
class MusicLyricsResult {
  const MusicLyricsResult({
    this.plainLyrics,
    this.syncedLyrics,
    this.trackName,
    this.artistName,
    this.albumName,
  });

  final String? plainLyrics;
  final String? syncedLyrics;
  final String? trackName;
  final String? artistName;
  final String? albumName;

  factory MusicLyricsResult.fromJson(Map<String, dynamic> json) {
    return MusicLyricsResult(
      plainLyrics: json['plainLyrics']?.toString(),
      syncedLyrics: json['syncedLyrics']?.toString(),
      trackName: json['trackName']?.toString(),
      artistName: json['artistName']?.toString(),
      albumName: json['albumName']?.toString(),
    );
  }

  /// 优先返回带时间轴的歌词，其次纯文本。
  String? get bestLyrics {
    final synced = syncedLyrics?.trim();
    if (synced != null && synced.isNotEmpty) {
      return synced;
    }
    final plain = plainLyrics?.trim();
    if (plain != null && plain.isNotEmpty) {
      return plain;
    }
    return null;
  }
}
