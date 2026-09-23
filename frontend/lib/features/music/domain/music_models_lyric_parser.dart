part of 'music_models.dart';

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
