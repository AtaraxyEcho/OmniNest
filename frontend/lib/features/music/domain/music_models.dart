class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.fileNodeId,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    required this.format,
    required this.favorite,
    this.durationSeconds,
    this.bitrate,
    this.sampleRate,
    this.fileSize,
    this.lyricsRaw,
    this.lyricsTranslation,
    this.lyricsWords,
    this.genre,
    this.coverUrl,
    this.updatedAt,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: json['id']?.toString() ?? '',
      fileNodeId: json['fileNodeId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled Track',
      artistName: json['artistName']?.toString() ?? 'Unknown Artist',
      albumTitle: json['albumTitle']?.toString() ?? 'Unknown Album',
      durationSeconds: _nullableInt(json['durationSeconds']),
      format: json['format']?.toString() ?? 'AUDIO',
      bitrate: _nullableInt(json['bitrate']),
      sampleRate: _nullableInt(json['sampleRate']),
      fileSize: _nullableInt(json['fileSize']),
      lyricsRaw: json['lyricsRaw']?.toString(),
      lyricsTranslation: json['lyricsTranslation']?.toString(),
      genre: json['genre']?.toString(),
      coverUrl: json['coverUrl']?.toString(),
      favorite: _asBool(json['favorite']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  final String id;
  final String fileNodeId;
  final String title;
  final String artistName;
  final String albumTitle;
  final int? durationSeconds;
  final String format;
  final int? bitrate;
  final int? sampleRate;
  final int? fileSize;
  final String? lyricsRaw;

  /// 歌词译文（独立于原文的 LRC 或纯文本），由在线平台提供。
  final String? lyricsTranslation;

  /// 逐字歌词载荷（网易云 `yrc`），由在线平台提供。
  ///
  /// 只在内存中随曲目对象流转：本地曲库与后端 DTO 都没有该字段，
  /// 换曲或重启后重新按需拉取。
  final String? lyricsWords;
  final String? genre;
  final String? coverUrl;
  final bool favorite;
  final DateTime? updatedAt;

  String get durationText {
    final total = durationSeconds ?? 0;
    if (total <= 0) return '--:--';
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get qualityText {
    final parts = <String>[];
    if (sampleRate != null && sampleRate! > 0) {
      final khz = sampleRate! / 1000;
      parts.add(
        '${khz.toStringAsFixed(khz.truncateToDouble() == khz ? 0 : 1)}kHz',
      );
    }
    if (bitrate != null && bitrate! > 0) parts.add('${bitrate}kbps');
    return parts.isEmpty ? format.toUpperCase() : parts.join(' / ');
  }

  List<MusicLyricLine> get lyricLines => parseMusicLyrics(
    lyricsRaw,
    translation: lyricsTranslation,
    wordLyrics: lyricsWords,
  );

  MusicTrack copyWith({
    bool? favorite,
    String? lyricsRaw,
    String? lyricsTranslation,
    String? lyricsWords,
    String? genre,
  }) {
    return MusicTrack(
      id: id,
      fileNodeId: fileNodeId,
      title: title,
      artistName: artistName,
      albumTitle: albumTitle,
      durationSeconds: durationSeconds,
      format: format,
      bitrate: bitrate,
      sampleRate: sampleRate,
      fileSize: fileSize,
      lyricsRaw: lyricsRaw ?? this.lyricsRaw,
      lyricsTranslation: lyricsTranslation ?? this.lyricsTranslation,
      lyricsWords: lyricsWords ?? this.lyricsWords,
      genre: genre ?? this.genre,
      coverUrl: coverUrl,
      favorite: favorite ?? this.favorite,
      updatedAt: updatedAt,
    );
  }
}

/// 词级时间片：相对所在行起始位置的偏移与时长。
///
/// 网易云 `yrc` 的逐字数据用绝对毫秒表达行与词的时间，解析后统一换算成
/// "相对行首"，渲染层只关心行内进度。
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

/// 解析歌词原文。
///
/// [translation] 为独立译文（LRC 或纯文本），按时间戳就近对齐；[wordLyrics]
/// 为平台逐字载荷（网易云 `yrc`），逐行匹配后挂到对应行的 [MusicLyricLine.words] 上。
List<MusicLyricLine> parseMusicLyrics(
  String? raw, {
  String? translation,
  String? wordLyrics,
}) {
  if (raw == null || raw.trim().isEmpty) {
    return const [];
  }
  final lines = <MusicLyricLine>[];
  final timestampPattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  final translationByPosition = _parseTranslationTimestamps(translation);
  final wordsByPosition = parseMusicLyricWords(wordLyrics);
  String? nearestText(Map<Duration, String> table, Duration position) {
    if (table.isEmpty) {
      return null;
    }
    // 优先精确毫秒匹配，其次取与原文时间差最小且不超过容差的译文行。
    final exact = table[position];
    if (exact != null) {
      return exact;
    }
    const tolerance = Duration(milliseconds: 500);
    String? best;
    Duration? bestDistance;
    for (final entry in table.entries) {
      final distance = (entry.key - position).abs();
      if (distance <= tolerance &&
          (bestDistance == null || distance < bestDistance)) {
        bestDistance = distance;
        best = entry.value;
      }
    }
    return best;
  }

  for (final rawLine in raw.split(RegExp(r'\r?\n'))) {
    final matches = timestampPattern.allMatches(rawLine).toList();
    if (matches.isEmpty) {
      continue;
    }
    final text = rawLine.replaceAll(timestampPattern, '').trim();
    if (text.isEmpty) {
      continue;
    }
    for (final match in matches) {
      final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
      final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
      final fraction = match.group(3) ?? '0';
      final millis = _lyricFractionToMilliseconds(fraction);
      final position = Duration(
        minutes: minutes,
        seconds: seconds,
        milliseconds: millis,
      );
      lines.add(
        MusicLyricLine(
          position: position,
          text: text,
          translation: nearestText(translationByPosition, position),
          words: _nearestWords(wordsByPosition, position),
        ),
      );
    }
  }
  lines.sort((left, right) => left.position.compareTo(right.position));
  return lines;
}

/// 解析逐字歌词载荷（网易云 `yrc`），返回"行起始时间 → 词列表"。
///
/// 行头为 `[行起始,行时长]`（毫秒，绝对时间），词元为 `(词起始,词时长,0)文本`，
/// 词时长按毫秒。开头的 `{"t":0,…}` 元数据行没有行头，天然被跳过；
/// 无法识别的行会被跳过；整段无法识别时返回空表，调用方退回行级显示。
Map<Duration, List<MusicLyricWord>> parseMusicLyricWords(String? raw) {
  final result = <Duration, List<MusicLyricWord>>{};
  if (raw == null || raw.trim().isEmpty) {
    return result;
  }
  final lineHeader = RegExp(r'^\[(\d+),(\d+)\]');
  final yrcWord = RegExp(r'\((\d+),(\d+),\d+\)([^()]*)');
  for (final rawLine in raw.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    final header = lineHeader.firstMatch(line);
    if (header == null) {
      continue;
    }
    final startMs = int.tryParse(header.group(1) ?? '');
    if (startMs == null) {
      continue;
    }
    final body = line.substring(header.end);
    final words = <MusicLyricWord>[];
    for (final match in yrcWord.allMatches(body)) {
      _addWord(words, match.group(3), match.group(1), match.group(2), startMs);
    }
    if (words.isEmpty) {
      continue;
    }
    final position = Duration(milliseconds: startMs);
    result.putIfAbsent(
      position,
      () => List<MusicLyricWord>.unmodifiable(words),
    );
  }
  return result;
}

void _addWord(
  List<MusicLyricWord> words,
  String? text,
  String? startMs,
  String? durationMs,
  int lineStartMs,
) {
  final start = int.tryParse(startMs ?? '');
  if (start == null || text == null) {
    return;
  }
  final duration = int.tryParse(durationMs ?? '') ?? 0;
  // 词时间戳是绝对时间：换算成相对行首，负值（异常数据）按 0 处理。
  final offset = start - lineStartMs;
  words.add(
    MusicLyricWord(
      offset: Duration(milliseconds: offset < 0 ? 0 : offset),
      duration: Duration(milliseconds: duration < 0 ? 0 : duration),
      text: text,
    ),
  );
}

/// 就近挂载词级数据：行起始时间精确匹配优先，其次 500ms 容差内取最近一行。
///
/// 词偏移是相对 yrc 行首的（见 `_addWord`），而消费方按 LRC 行首计算行内进度。
/// 按容差命中相邻行时必须把两份行首的时间差补回偏移，否则整块词级时间相对
/// 人声恒定提前或滞后（逐字填充跟不上唱词）。精确匹配无位移，仍复用原列表实例。
///
/// 位移后的偏移允许为负：yrc 行首早于 LRC 行首时，前导词元在 LRC 锚点时刻已经
/// 唱了一部分，[MusicLyricLine.fillStateAt] 按负偏移计入这段已唱时长。把负值夹到
/// 0 会让行首若干词元同时起唱，表现为填充领先人声后再错位。
List<MusicLyricWord> _nearestWords(
  Map<Duration, List<MusicLyricWord>> table,
  Duration position,
) {
  if (table.isEmpty) {
    return const <MusicLyricWord>[];
  }
  final exact = table[position];
  if (exact != null) {
    return exact;
  }
  const tolerance = Duration(milliseconds: 500);
  List<MusicLyricWord>? best;
  Duration? bestStart;
  Duration? bestDistance;
  for (final entry in table.entries) {
    final distance = (entry.key - position).abs();
    if (distance <= tolerance &&
        (bestDistance == null || distance < bestDistance)) {
      bestDistance = distance;
      bestStart = entry.key;
      best = entry.value;
    }
  }
  if (best == null || bestStart == null) {
    return const <MusicLyricWord>[];
  }
  final shift = bestStart - position;
  if (shift == Duration.zero) {
    return best;
  }
  return List<MusicLyricWord>.unmodifiable([
    for (final word in best)
      MusicLyricWord(
        offset: word.offset + shift,
        duration: word.duration,
        text: word.text,
      ),
  ]);
}

/// 解析译文时间轴；纯文本译文返回空表（逐行文本交给行级回退处理）。
Map<Duration, String> _parseTranslationTimestamps(String? translation) {
  final result = <Duration, String>{};
  if (translation == null || translation.trim().isEmpty) {
    return result;
  }
  final timestampPattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  for (final rawLine in translation.split(RegExp(r'\r?\n'))) {
    final matches = timestampPattern.allMatches(rawLine).toList();
    if (matches.isEmpty) {
      continue;
    }
    final text = rawLine.replaceAll(timestampPattern, '').trim();
    if (text.isEmpty) {
      continue;
    }
    final match = matches.first;
    final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
    final fraction = match.group(3) ?? '0';
    final millis = _lyricFractionToMilliseconds(fraction);
    result.putIfAbsent(
      Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
      () => text,
    );
  }
  return result;
}

int _lyricFractionToMilliseconds(String fraction) {
  if (fraction.isEmpty) {
    return 0;
  }
  final digits = fraction.length >= 3 ? fraction.substring(0, 3) : fraction;
  final value = int.tryParse(digits) ?? 0;
  if (digits.length == 1) {
    return value * 100;
  }
  if (digits.length == 2) {
    return value * 10;
  }
  return value;
}

class MusicAlbum {
  const MusicAlbum({
    required this.id,
    required this.title,
    required this.artistName,
    required this.trackCount,
    this.coverUrl,
    this.releaseDate,
    this.totalDuration,
    this.updatedAt,
  });

  factory MusicAlbum.fromJson(Map<String, dynamic> json) {
    return MusicAlbum(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown Album',
      artistName: json['artistName']?.toString() ?? 'Unknown Artist',
      coverUrl: json['coverUrl']?.toString(),
      releaseDate: _parseDateTime(json['releaseDate']),
      totalDuration: _nullableInt(json['totalDuration']),
      trackCount: _asInt(json['trackCount']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  final String id;
  final String title;
  final String artistName;
  final String? coverUrl;
  final DateTime? releaseDate;
  final int? totalDuration;
  final int trackCount;
  final DateTime? updatedAt;
}

class MusicArtist {
  const MusicArtist({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.albumCount,
    this.avatarUrl,
    this.updatedAt,
  });

  factory MusicArtist.fromJson(Map<String, dynamic> json) {
    return MusicArtist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Artist',
      avatarUrl: json['avatarUrl']?.toString(),
      trackCount: _asInt(json['trackCount']),
      albumCount: _asInt(json['albumCount']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  final String id;
  final String name;
  final String? avatarUrl;
  final int trackCount;
  final int albumCount;
  final DateTime? updatedAt;
}

class MusicPlaylist {
  const MusicPlaylist({
    required this.id,
    required this.name,
    required this.playlistType,
    required this.trackCount,
    this.description,
    this.coverFileId,
    this.coverUrl,
    this.updatedAt,
  });

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) {
    return MusicPlaylist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled Playlist',
      description: json['description']?.toString(),
      playlistType: json['playlistType']?.toString() ?? 'CUSTOM',
      coverFileId: json['coverFileId']?.toString(),
      coverUrl: json['coverUrl']?.toString(),
      trackCount: _asInt(json['trackCount']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  final String id;
  final String name;
  final String? description;
  final String playlistType;
  final String? coverFileId;
  final String? coverUrl;
  final int trackCount;
  final DateTime? updatedAt;

  MusicPlaylist copyWith({int? trackCount}) {
    return MusicPlaylist(
      id: id,
      name: name,
      description: description,
      playlistType: playlistType,
      coverFileId: coverFileId,
      coverUrl: coverUrl,
      trackCount: trackCount ?? this.trackCount,
      updatedAt: updatedAt,
    );
  }
}

class MusicPlaybackPlan {
  const MusicPlaybackPlan({
    required this.trackId,
    required this.url,
    this.expiresAt,
    this.durationSeconds,
    this.format,
    this.quality,
  });

  factory MusicPlaybackPlan.fromJson(Map<String, dynamic> json) {
    return MusicPlaybackPlan(
      trackId: json['trackId']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      expiresAt: _parseDateTime(json['expiresAt']),
      durationSeconds: _nullableInt(json['durationSeconds']),
      format: json['format']?.toString(),
      quality: json['quality']?.toString(),
    );
  }

  final String trackId;
  final String url;
  final DateTime? expiresAt;
  final int? durationSeconds;
  final String? format;

  /// 在线曲目由平台实际签发的音质档位（如 lossless / exhigh）；
  /// 本地曲目为 null（真实采样率/码率在曲目元数据上）。
  final String? quality;

  MusicPlaybackPlan copyWith({
    String? trackId,
    String? url,
    DateTime? expiresAt,
    int? durationSeconds,
    String? format,
    String? quality,
  }) {
    return MusicPlaybackPlan(
      trackId: trackId ?? this.trackId,
      url: url ?? this.url,
      expiresAt: expiresAt ?? this.expiresAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      format: format ?? this.format,
      quality: quality ?? this.quality,
    );
  }
}

class MusicPlaybackPosition {
  const MusicPlaybackPosition({
    required this.trackId,
    required this.positionSeconds,
  });

  factory MusicPlaybackPosition.fromJson(Map<String, dynamic> json) {
    return MusicPlaybackPosition(
      trackId: json['trackId']?.toString() ?? '',
      positionSeconds: _asInt(json['positionSeconds']),
    );
  }

  final String trackId;
  final int positionSeconds;
}

/// 本地与服务端共享的音乐播放进度快照。
class MusicPlaybackProgress {
  const MusicPlaybackProgress({
    required this.playableKey,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.completed,
    required this.updatedAt,
    this.version = 0,
  });

  factory MusicPlaybackProgress.fromJson(Map<String, dynamic> json) {
    return MusicPlaybackProgress(
      playableKey: json['playableKey']?.toString() ?? '',
      positionSeconds: _asInt(json['positionSeconds']),
      durationSeconds: _asInt(json['durationSeconds']),
      completed: _asBool(json['completed']),
      updatedAt:
          _parseDateTime(json['updatedAt'] ?? json['clientUpdatedAt']) ??
          DateTime.now(),
      version: _asInt(json['version']),
    );
  }

  final String playableKey;
  final int positionSeconds;
  final int durationSeconds;
  final bool completed;
  final DateTime updatedAt;
  final int version;

  double get progressPercent {
    if (durationSeconds <= 0) {
      return 0;
    }
    return (positionSeconds * 100 / durationSeconds)
        .clamp(0.0, 100.0)
        .toDouble();
  }

  Map<String, dynamic> toSaveJson() {
    return {
      'playableKey': playableKey,
      'positionSeconds': positionSeconds,
      'durationSeconds': durationSeconds,
      'completed': completed,
      'clientUpdatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }
}

class MusicDashboard {
  const MusicDashboard({
    required this.trackCount,
    required this.albumCount,
    required this.artistCount,
    required this.playHistoryCount,
    required this.recentTracks,
    required this.recentAlbums,
    required this.featuredArtists,
  });

  factory MusicDashboard.empty() {
    return const MusicDashboard(
      trackCount: 0,
      albumCount: 0,
      artistCount: 0,
      playHistoryCount: 0,
      recentTracks: [],
      recentAlbums: [],
      featuredArtists: [],
    );
  }

  factory MusicDashboard.fromJson(Map<String, dynamic> json) {
    return MusicDashboard(
      trackCount: _asInt(json['trackCount']),
      albumCount: _asInt(json['albumCount']),
      artistCount: _asInt(json['artistCount']),
      playHistoryCount: _asInt(json['playHistoryCount']),
      recentTracks:
          _asMapList(json['recentTracks']).map(MusicTrack.fromJson).toList(),
      recentAlbums:
          _asMapList(json['recentAlbums']).map(MusicAlbum.fromJson).toList(),
      featuredArtists:
          _asMapList(
            json['featuredArtists'],
          ).map(MusicArtist.fromJson).toList(),
    );
  }

  final int trackCount;
  final int albumCount;
  final int artistCount;
  final int playHistoryCount;
  final List<MusicTrack> recentTracks;
  final List<MusicAlbum> recentAlbums;
  final List<MusicArtist> featuredArtists;
}

class MusicSearchResult {
  const MusicSearchResult({
    required this.tracks,
    required this.albums,
    required this.artists,
  });

  factory MusicSearchResult.fromJson(Map<String, dynamic> json) {
    return MusicSearchResult(
      tracks: _asMapList(json['tracks']).map(MusicTrack.fromJson).toList(),
      albums: _asMapList(json['albums']).map(MusicAlbum.fromJson).toList(),
      artists: _asMapList(json['artists']).map(MusicArtist.fromJson).toList(),
    );
  }

  final List<MusicTrack> tracks;
  final List<MusicAlbum> albums;
  final List<MusicArtist> artists;
}

class MusicScanJob {
  const MusicScanJob({
    required this.id,
    required this.status,
    required this.progress,
    required this.scannedFiles,
    this.message,
    this.details,
    this.createdAt,
  });

  factory MusicScanJob.fromJson(Map<String, dynamic> json) {
    return MusicScanJob(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PENDING',
      progress: _asInt(json['progress']),
      scannedFiles: _asInt(json['scannedFiles']),
      message: json['message']?.toString(),
      details: json['details']?.toString(),
      createdAt: _parseDateTime(json['createdAt']),
    );
  }

  final String id;
  final String status;
  final int progress;
  final int scannedFiles;
  final String? message;
  final String? details;
  final DateTime? createdAt;
}

class MusicScrapeCandidate {
  const MusicScrapeCandidate({
    required this.provider,
    required this.externalId,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    this.releaseDate,
    this.durationSeconds,
    this.trackNumber,
    this.discNumber,
    this.coverUrl,
    this.score,
    this.externalIds = const {},
    this.providerMetadata = const {},
  });

  factory MusicScrapeCandidate.fromJson(Map<String, dynamic> json) {
    return MusicScrapeCandidate(
      provider: json['provider']?.toString() ?? '',
      externalId: json['externalId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled Track',
      artistName: json['artistName']?.toString() ?? 'Unknown Artist',
      albumTitle: json['albumTitle']?.toString() ?? 'Unknown Album',
      releaseDate: _parseDateTime(json['releaseDate']),
      durationSeconds: _nullableInt(json['durationSeconds']),
      trackNumber: _nullableInt(json['trackNumber']),
      discNumber: _nullableInt(json['discNumber']),
      coverUrl: json['coverUrl']?.toString(),
      score: _nullableInt(json['score']),
      externalIds: _asMap(json['externalIds']),
      providerMetadata: _asMap(json['providerMetadata']),
    );
  }

  final String provider;
  final String externalId;
  final String title;
  final String artistName;
  final String albumTitle;
  final DateTime? releaseDate;
  final int? durationSeconds;
  final int? trackNumber;
  final int? discNumber;
  final String? coverUrl;
  final int? score;
  final Map<String, dynamic> externalIds;
  final Map<String, dynamic> providerMetadata;

  String get releaseText {
    final date = releaseDate;
    if (date == null) return 'Unknown date';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String get scoreText => score == null ? '--' : '$score';

  Map<String, dynamic> toApplyJson() {
    return {
      'provider': provider,
      'externalId': externalId,
      'title': title,
      'artistName': artistName,
      'albumTitle': albumTitle,
      'releaseDate': releaseDate?.toIso8601String().split('T').first,
      'durationSeconds': durationSeconds,
      'trackNumber': trackNumber,
      'discNumber': discNumber,
      'coverUrl': coverUrl,
      'score': score,
      'externalIds': externalIds,
      'providerMetadata': providerMetadata,
    };
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableInt(dynamic value) {
  if (value == null || value.toString().isEmpty) return null;
  return _asInt(value);
}

bool _asBool(dynamic value) {
  if (value is bool) return value;
  return value?.toString().toLowerCase() == 'true';
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null || value.toString().isEmpty) return null;
  return DateTime.tryParse(value.toString().replaceFirst(' ', 'T'))?.toLocal();
}

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is! Map) return const {};
  return Map<String, dynamic>.from(value);
}

/// 在线搜索曲目（来自网易云）
class OnlineTrack {
  const OnlineTrack({
    required this.platform,
    required this.songId,
    required this.title,
    required this.artistName,
    this.albumTitle = '',
    this.coverUrl = '',
    this.durationSeconds,
    this.quality,

    this.extra = const {},
  });

  final String platform;
  final String songId;
  final String title;
  final String artistName;
  final String albumTitle;
  final String coverUrl;
  final int? durationSeconds;
  final String? quality;

  final Map<String, dynamic> extra;

  String get durationText {
    if (durationSeconds == null || durationSeconds! <= 0) return '';
    final m = durationSeconds! ~/ 60;
    final s = durationSeconds! % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  factory OnlineTrack.fromJson(Map<String, dynamic> json) {
    final extra =
        json['extra'] is Map
            ? Map<String, dynamic>.from(json['extra'] as Map)
            : const <String, dynamic>{};
    return OnlineTrack(
      platform: json['platform']?.toString() ?? '',
      songId: json['songId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      artistName: json['artistName']?.toString() ?? '',
      albumTitle: json['albumTitle']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      durationSeconds: _nullableInt(json['durationSeconds']),
      quality: json['quality']?.toString(),

      extra: extra,
    );
  }
}

/// 外部平台每日推荐歌曲。
class DailyRecommendedTracks {
  const DailyRecommendedTracks({
    required this.platform,
    required this.recommendationDate,
    required this.tracks,
  });

  final String platform;
  final DateTime recommendationDate;
  final List<OnlineTrack> tracks;

  String get coverUrl => tracks
      .map((track) => track.coverUrl.trim())
      .firstWhere((url) => url.isNotEmpty, orElse: () => '');

  factory DailyRecommendedTracks.fromJson(Map<String, dynamic> json) {
    return DailyRecommendedTracks(
      platform: json['platform']?.toString() ?? '',
      recommendationDate:
          DateTime.tryParse(json['recommendationDate']?.toString() ?? '') ??
          DateTime.now(),
      tracks: _asMapList(
        json['tracks'],
      ).map(OnlineTrack.fromJson).toList(growable: false),
    );
  }
}

/// 在线平台歌单
class OnlinePlaylist {
  const OnlinePlaylist({
    required this.platform,
    required this.playlistId,
    required this.name,
    this.description = '',
    this.coverUrl = '',
    this.trackCount,
    this.ownerName = '',
    this.subscribed = false,
    this.extra = const {},
  });

  final String platform;
  final String playlistId;
  final String name;
  final String description;
  final String coverUrl;
  final int? trackCount;
  final String ownerName;
  final bool subscribed;
  final Map<String, dynamic> extra;

  factory OnlinePlaylist.fromJson(Map<String, dynamic> json) => OnlinePlaylist(
    platform: json['platform']?.toString() ?? '',
    playlistId: json['playlistId']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    coverUrl: json['coverUrl']?.toString() ?? '',
    trackCount: _nullableInt(json['trackCount']),
    ownerName: json['ownerName']?.toString() ?? '',
    subscribed: _asBool(json['subscribed']),
    extra: _asMap(json['extra']),
  );
}

/// 本地和在线音乐统一最近播放记录。
class MusicRecentEntry {
  const MusicRecentEntry({
    required this.playableKey,
    required this.playedAt,
    this.localTrack,
    this.onlineTrack,
  });

  final String playableKey;
  final MusicTrack? localTrack;
  final OnlineTrack? onlineTrack;
  final DateTime playedAt;

  factory MusicRecentEntry.fromJson(Map<String, dynamic> json) {
    final localTrack = json['localTrack'];
    final onlineTrack = json['onlineTrack'];
    return MusicRecentEntry(
      playableKey: json['playableKey']?.toString() ?? '',
      localTrack:
          localTrack is Map
              ? MusicTrack.fromJson(Map<String, dynamic>.from(localTrack))
              : null,
      onlineTrack:
          onlineTrack is Map
              ? OnlineTrack.fromJson(Map<String, dynamic>.from(onlineTrack))
              : null,
      playedAt: _parseDateTime(json['playedAt']) ?? DateTime.now(),
    );
  }
}

/// 播放历史条目，覆盖本地与在线播放来源。
class MusicPlayHistoryEntry {
  const MusicPlayHistoryEntry({
    required this.playableKey,
    required this.title,
    required this.artistName,
    required this.playedAt,
    this.albumTitle,
    this.coverUrl,
    this.durationSeconds,
    this.platform,
  });

  final String playableKey;
  final String title;
  final String artistName;
  final String? albumTitle;
  final String? coverUrl;
  final int? durationSeconds;
  final String? platform;
  final DateTime playedAt;

  factory MusicPlayHistoryEntry.fromJson(Map<String, dynamic> json) {
    return MusicPlayHistoryEntry(
      playableKey: json['playableKey']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      artistName: json['artistName']?.toString() ?? '',
      albumTitle: json['albumTitle']?.toString(),
      coverUrl: json['coverUrl']?.toString(),
      durationSeconds:
          json['durationSeconds'] is num
              ? (json['durationSeconds'] as num).toInt()
              : null,
      platform: json['platform']?.toString(),
      playedAt: _parseDateTime(json['playedAt']) ?? DateTime.now(),
    );
  }
}

/// 在线平台能力
class MusicPlatformCapabilities {
  const MusicPlatformCapabilities({
    this.search = false,
    this.playlists = false,
    this.likedTracks = false,
    this.lyrics = false,
    this.dailyRecommendations = false,
    this.qualityLevels = const [],
  });

  final bool search;
  final bool playlists;
  final bool likedTracks;
  final bool lyrics;
  final bool dailyRecommendations;
  final List<String> qualityLevels;

  factory MusicPlatformCapabilities.fromJson(Map<String, dynamic> json) =>
      MusicPlatformCapabilities(
        search: _asBool(json['search']),
        playlists: _asBool(json['playlists']),
        likedTracks: _asBool(json['likedTracks']),
        lyrics: _asBool(json['lyrics']),
        dailyRecommendations: _asBool(json['dailyRecommendations']),
        qualityLevels:
            json['qualityLevels'] is List
                ? (json['qualityLevels'] as List)
                    .map((item) => item.toString())
                    .toList()
                : const [],
      );
}

/// QR 登录会话
class QrLoginSession {
  const QrLoginSession({
    required this.loginKey,
    this.qrUrl,
    this.qrImageBase64,
  });

  final String loginKey;
  final String? qrUrl;
  final String? qrImageBase64;

  factory QrLoginSession.fromJson(Map<String, dynamic> json) => QrLoginSession(
    loginKey: json['loginKey']?.toString() ?? '',
    qrUrl: json['qrUrl']?.toString(),
    qrImageBase64: json['qrImageBase64']?.toString(),
  );
}

/// QR 登录状态
class QrLoginStatus {
  const QrLoginStatus({required this.status, this.userInfo});

  final String status;
  final PlatformUserInfo? userInfo;

  factory QrLoginStatus.fromJson(Map<String, dynamic> json) {
    final raw = json['userInfo'];
    return QrLoginStatus(
      status: json['status']?.toString() ?? '',
      userInfo:
          raw is Map
              ? PlatformUserInfo.fromJson(Map<String, dynamic>.from(raw))
              : null,
    );
  }
}

/// 平台用户信息
class PlatformUserInfo {
  const PlatformUserInfo({
    required this.platform,
    this.userId = '',
    this.nickname = '',
    this.avatarUrl = '',
    this.vip = false,
  });

  final String platform;
  final String userId;
  final String nickname;
  final String avatarUrl;
  final bool vip;

  factory PlatformUserInfo.fromJson(Map<String, dynamic> json) =>
      PlatformUserInfo(
        platform: json['platform']?.toString() ?? '',
        userId: json['userId']?.toString() ?? '',
        nickname: json['nickname']?.toString() ?? '',
        avatarUrl: json['avatarUrl']?.toString() ?? '',
        vip: json['vip'] == true,
      );
}

/// 在线平台连接状态
class MusicPlatformStatus {
  const MusicPlatformStatus({
    required this.platform,
    required this.displayName,
    required this.enabled,
    required this.connected,
    required this.capabilities,
    this.userInfo,
    this.lastVerifiedAt,
    this.recoverableErrors = const [],
  });

  final String platform;
  final String displayName;
  final bool enabled;
  final bool connected;
  final PlatformUserInfo? userInfo;
  final MusicPlatformCapabilities capabilities;
  final DateTime? lastVerifiedAt;
  final List<String> recoverableErrors;

  factory MusicPlatformStatus.fromJson(Map<String, dynamic> json) {
    final rawUserInfo = json['userInfo'];
    return MusicPlatformStatus(
      platform: json['platform']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      enabled: _asBool(json['enabled']),
      connected: _asBool(json['connected']),
      userInfo:
          rawUserInfo is Map
              ? PlatformUserInfo.fromJson(
                Map<String, dynamic>.from(rawUserInfo),
              )
              : null,
      capabilities: MusicPlatformCapabilities.fromJson(
        _asMap(json['capabilities']),
      ),
      lastVerifiedAt: _parseDateTime(json['lastVerifiedAt']),
      recoverableErrors:
          json['recoverableErrors'] is List
              ? (json['recoverableErrors'] as List)
                  .map((item) => item.toString())
                  .toList()
              : const [],
    );
  }
}

/// 音乐曲库分页结果，与后端 PageResponse 对齐。
class MusicPagedResult<T> {
  const MusicPagedResult({
    required this.items,
    this.page = 0,
    this.size = 0,
    this.totalElements = 0,
  });

  final List<T> items;
  final int page;
  final int size;
  final int totalElements;

  bool get hasMore => (page + 1) * size < totalElements;
}

/// 在线平台歌词：原文、独立译文与逐字载荷。
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
