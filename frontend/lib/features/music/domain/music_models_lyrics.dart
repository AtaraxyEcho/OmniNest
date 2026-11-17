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

  /// 译文行（按时间戳就近对齐）。
  final String? translation;

  /// 词级时间轴：为空表示只有行级时间戳（本地 LRC 或平台未返回逐字数据）。
  ///
  /// 词级数据缺失时渲染层按"行时长线性估算"回退填充，不再整行读色。
  final List<MusicLyricWord> words;

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

  /// 行内时间 [withinLine] 处的填充进度，以及补间可以安全推进到的下一个目标。
  ///
  /// 只有非空白词元计入演唱时长：`yrc` 承载句末静默的空白词元不再被当成演唱，
  /// 唱完最后一个词即停在满格。[nextFraction] 是下一个变化点的进度——正在唱的
  /// 词元结束时其完整进度，或落在词间空隙时维持原值——[toNextFraction] 是到达
  /// 那里的时长。补间若直接推到 1.0，就会把空隙（间奏）时长算进填充进度。
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
        // 词间空隙：进度原地保持，补间只推进到下一个词元的起点。
        final current = ratio(completedMs);
        return (
          fraction: current,
          nextFraction: current,
          toNextFraction: word.offset - withinLine,
        );
      }
      final beforeMs = completedMs;
      if (withinLine < end) {
        // 正在演唱该词元：按已唱时长推进，补间目标为该词元结束处。
        completedMs += (withinLine - word.offset).inMilliseconds;
        return (
          fraction: ratio(completedMs),
          nextFraction: ratio(beforeMs + word.duration.inMilliseconds),
          toNextFraction: end - withinLine,
        );
      }
      completedMs = beforeMs + word.duration.inMilliseconds;
    }
    // 全部词元已唱完：保持满格，之后的间奏不再计入进度。
    return (fraction: 1.0, nextFraction: 1.0, toNextFraction: Duration.zero);
  }

  /// 无词级时间轴时的演唱时长估算：字符数 × 平均语速，并以 [span]（本行与
  /// 下一行的间隙）封顶。让行级歌词的填充在唱完后停在满格，而不是把整段
  /// 间隙（含间奏）线性摊完。
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
}

class MusicPlatformLyrics {
  const MusicPlatformLyrics({
    required this.lyrics,
    this.translation,
    this.words,
  });

  final String lyrics;
  final String? translation;

  /// 逐字歌词原始载荷（网易云 `yrc`），平台不提供时为 null。
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
