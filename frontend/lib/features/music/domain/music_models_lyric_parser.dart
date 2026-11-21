part of 'music_models.dart';

/// 解析歌词原文。
///
/// 支持：
/// - 标准 LRC（含同时间戳 `<=20ms` 双行 LRC 自动合并为原文+译文）
/// - 增强 LRC（`ELRC` 行内 `<mm:ss.xx>word` 逐字时间戳）
/// - 网易云 `yrc`（`[startMs,durMs](wordStartMs,wordDurMs,0)text`）与行级 JSON
/// - 酷狗 `krc`（`[startMs,durMs]<offsetMs,durMs,0>word`）
///
/// [translation] 为独立译文（LRC 或纯文本），按时间戳就近对齐；[wordLyrics]
/// 为逐字载荷（`yrc` / `elrc` / `krc`），逐行匹配后挂到对应行的 [MusicLyricLine.words] 上。
List<MusicLyricLine> parseMusicLyrics(
  String? raw, {
  String? translation,
  String? wordLyrics,
}) {
  final normalizedRaw = _normalizeMusicLyricText(raw);
  if (normalizedRaw == null || normalizedRaw.trim().isEmpty) {
    return const [];
  }
  final lines = <MusicLyricLine>[];
  final timestampPattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  final elrcWordPattern = RegExp(r'<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>');
  final yrcOrKrcHeaderPattern = RegExp(r'^\[(\d+),(\d+)\]');

  final translationByPosition = _parseTranslationTimestamps(
    _normalizeMusicLyricText(translation),
  );
  final wordsByPosition = parseMusicLyricWords(
    _normalizeMusicLyricText(wordLyrics),
  );

  String? nearestText(Map<Duration, String> table, Duration position) {
    if (table.isEmpty) {
      return null;
    }
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

  for (final rawLine in normalizedRaw.split(RegExp(r'\r?\n'))) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) continue;

    final structured = _parseNeteaseLyricJsonLine(trimmed);
    if (structured != null) {
      lines.add(
        MusicLyricLine(
          position: structured.position,
          text: structured.text,
          translation: nearestText(translationByPosition, structured.position),
          words: _nearestWords(wordsByPosition, structured.position),
        ),
      );
      continue;
    }

    final matches = timestampPattern.allMatches(rawLine).toList();
    if (matches.isEmpty) {
      final header = yrcOrKrcHeaderPattern.firstMatch(trimmed);
      if (header != null) {
        final startMs = int.tryParse(header.group(1) ?? '');
        if (startMs != null) {
          final body = trimmed.substring(header.end);
          final parsedWords = _parseYrcOrKrcBodyWords(body, startMs);
          final text =
              parsedWords.isNotEmpty
                  ? parsedWords.map((w) => w.text).join().trim()
                  : _yrcLineText(body);
          if (text.isNotEmpty) {
            final position = Duration(milliseconds: startMs);
            final matchedWords = _nearestWords(wordsByPosition, position);
            lines.add(
              MusicLyricLine(
                position: position,
                text: text,
                translation: nearestText(translationByPosition, position),
                words:
                    matchedWords.isNotEmpty
                        ? matchedWords
                        : List<MusicLyricWord>.unmodifiable(parsedWords),
              ),
            );
          }
        }
      }
      continue;
    }

    final bodyAfterTimestamps = rawLine.replaceAll(timestampPattern, '');
    final hasInlineElrc = elrcWordPattern.hasMatch(bodyAfterTimestamps);
    final cleanText =
        hasInlineElrc
            ? bodyAfterTimestamps.replaceAll(elrcWordPattern, '').trim()
            : bodyAfterTimestamps.trim();
    if (cleanText.isEmpty) {
      continue;
    }

    for (final match in matches) {
      final position = _durationFromLrcMatch(match);
      final externalWords = _nearestWords(wordsByPosition, position);
      final inlineWords =
          externalWords.isEmpty && hasInlineElrc
              ? _parseElrcInlineWords(bodyAfterTimestamps, position)
              : const <MusicLyricWord>[];
      lines.add(
        MusicLyricLine(
          position: position,
          text: cleanText,
          translation: nearestText(translationByPosition, position),
          words: externalWords.isNotEmpty ? externalWords : inlineWords,
        ),
      );
    }
  }

  lines.sort((left, right) => left.position.compareTo(right.position));

  // 同时间戳（<=20ms）双行 LRC 自动合并为双语对照（原文在上、译文在下）。
  if (lines.length < 2) {
    return lines;
  }
  const mergeThreshold = Duration(milliseconds: 20);
  final merged = <MusicLyricLine>[];
  var index = 0;
  while (index < lines.length) {
    final current = lines[index];
    if (index + 1 < lines.length) {
      final next = lines[index + 1];
      final diff = (next.position - current.position).abs();
      if (diff <= mergeThreshold &&
          !current.hasTranslation &&
          next.text.trim().isNotEmpty &&
          next.text.trim() != current.text.trim()) {
        merged.add(
          current.copyWith(
            translation: next.text.trim(),
            words: current.words.isNotEmpty ? current.words : next.words,
          ),
        );
        index += 2;
        continue;
      }
    }
    merged.add(current);
    index += 1;
  }
  return merged;
}

Duration _durationFromLrcMatch(RegExpMatch match) {
  final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
  final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
  final fraction = match.group(3) ?? '0';
  final millis = _lyricFractionToMilliseconds(fraction);
  return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
}

/// 解析增强 LRC 行内 `<mm:ss.xx>word` 逐字时间戳。
List<MusicLyricWord> _parseElrcInlineWords(String body, Duration linePosition) {
  final elrcTag = RegExp(r'<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>');
  final matches = elrcTag.allMatches(body).toList(growable: false);
  if (matches.isEmpty) return const <MusicLyricWord>[];

  final words = <MusicLyricWord>[];
  final lineStartMs = linePosition.inMilliseconds;

  // 若首个 `<mm:ss.xx>` 前有文本，视作从行首到首个标签的词元。
  final leading = body.substring(0, matches.first.start);
  if (leading.isNotEmpty) {
    final firstStartMs = _durationFromLrcMatch(matches.first).inMilliseconds;
    final durMs = (firstStartMs - lineStartMs).clamp(0, 60000);
    final leadingSpan = Duration(milliseconds: durMs > 0 ? durMs : 300);
    words.add(
      MusicLyricWord(
        offset: Duration.zero,
        duration: leadingSpan,
        text: leading,
      ),
    );
  }

  for (var i = 0; i < matches.length; i++) {
    final currentMatch = matches[i];
    final wordStartMs = _durationFromLrcMatch(currentMatch).inMilliseconds;
    final textEnd = i + 1 < matches.length ? matches[i + 1].start : body.length;
    final wordText = body.substring(currentMatch.end, textEnd);
    if (wordText.isEmpty) continue;
    final nextStartMs =
        i + 1 < matches.length
            ? _durationFromLrcMatch(matches[i + 1]).inMilliseconds
            : wordStartMs + 600;
    final offsetMs = wordStartMs - lineStartMs;
    final durMs = nextStartMs - wordStartMs;
    final wordSpan = Duration(milliseconds: durMs > 0 ? durMs : 300);
    words.add(
      MusicLyricWord(
        offset: Duration(milliseconds: offsetMs < 0 ? 0 : offsetMs),
        duration: wordSpan,
        text: wordText,
      ),
    );
  }
  return List<MusicLyricWord>.unmodifiable(words);
}

/// 解析单行 YRC `(absStartMs,durMs,0)text` 或 KRC `<offsetMs,durMs,0>text` 词元列表。
List<MusicLyricWord> _parseYrcOrKrcBodyWords(String body, int lineStartMs) {
  final yrcWord = RegExp(r'\((\d+),(\d+),\d+\)([^()]*)');
  final krcWord = RegExp(r'<(\d+),(\d+),\d+>([^<>]*)');

  final words = <MusicLyricWord>[];
  final yrcMatches = yrcWord.allMatches(body).toList(growable: false);
  if (yrcMatches.isNotEmpty) {
    for (final match in yrcMatches) {
      _addWord(
        words,
        match.group(3),
        match.group(1),
        match.group(2),
        lineStartMs,
      );
    }
    return words;
  }

  final krcMatches = krcWord.allMatches(body).toList(growable: false);
  if (krcMatches.isNotEmpty) {
    for (final match in krcMatches) {
      final offset = int.tryParse(match.group(1) ?? '');
      final duration = int.tryParse(match.group(2) ?? '') ?? 0;
      final text = match.group(3);
      if (offset == null || text == null) continue;
      final span = Duration(milliseconds: duration < 0 ? 0 : duration);
      words.add(
        MusicLyricWord(
          offset: Duration(milliseconds: offset < 0 ? 0 : offset),
          duration: span,
          text: text,
        ),
      );
    }
  }
  return words;
}

/// 网易云逐字歌词的行级 JSON 载荷。
_StructuredMusicLyricLine? _parseNeteaseLyricJsonLine(String line) {
  if (!line.startsWith('{') && !line.startsWith('[')) {
    return null;
  }
  try {
    final decoded = jsonDecode(line);
    if (decoded is Map) {
      return _structuredLineFromJson(decoded);
    }
    if (decoded is List && decoded.length == 1 && decoded.first is Map) {
      return _structuredLineFromJson(decoded.first as Map);
    }
  } on FormatException {
    // 不是 JSON 的歌词行继续按 LRC/YRC/KRC 解析。
  }
  return null;
}

_StructuredMusicLyricLine? _structuredLineFromJson(Map value) {
  final startMs = _lyricMilliseconds(value['t']);
  final content = value['c'];
  if (startMs == null || content is! List) {
    return null;
  }
  final text =
      content
          .map((part) => part is Map ? part['tx']?.toString() ?? '' : '')
          .join();
  if (text.trim().isEmpty) {
    return null;
  }
  return _StructuredMusicLyricLine(
    position: Duration(milliseconds: startMs),
    text: text.trim(),
  );
}

int? _lyricMilliseconds(Object? value) {
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '');
}

String _yrcLineText(String body) {
  final wordPattern = RegExp(r'\((\d+),(\d+),\d+\)([^()]*)');
  final yrc =
      wordPattern
          .allMatches(body)
          .map((match) => match.group(3) ?? '')
          .join()
          .trim();
  if (yrc.isNotEmpty) return yrc;
  final krcPattern = RegExp(r'<(\d+),(\d+),\d+>([^<>]*)');
  return krcPattern
      .allMatches(body)
      .map((match) => match.group(3) ?? '')
      .join()
      .trim();
}

class _StructuredMusicLyricLine {
  const _StructuredMusicLyricLine({required this.position, required this.text});

  final Duration position;
  final String text;
}

/// 解析逐字歌词载荷（支持网易云 `yrc`、酷狗 `krc` 与增强 LRC `elrc`），
/// 返回「行起始时间 → 词列表」。
Map<Duration, List<MusicLyricWord>> parseMusicLyricWords(String? raw) {
  final result = <Duration, List<MusicLyricWord>>{};
  final normalizedRaw = _normalizeMusicLyricText(raw);
  if (normalizedRaw == null || normalizedRaw.trim().isEmpty) {
    return result;
  }
  final yrcOrKrcHeader = RegExp(r'^\[(\d+),(\d+)\]');
  final lrcTimestamp = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  final elrcTag = RegExp(r'<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>');

  for (final rawLine in normalizedRaw.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    final header = yrcOrKrcHeader.firstMatch(line);
    if (header != null) {
      final startMs = int.tryParse(header.group(1) ?? '');
      if (startMs == null) continue;
      final body = line.substring(header.end);
      final words = _parseYrcOrKrcBodyWords(body, startMs);
      if (words.isEmpty) continue;
      final position = Duration(milliseconds: startMs);
      result.putIfAbsent(
        position,
        () => List<MusicLyricWord>.unmodifiable(words),
      );
      continue;
    }

    // 增强 LRC（ELRC）：`[mm:ss.xx]<mm:ss.xx>word...`
    final lrcMatches = lrcTimestamp.allMatches(line).toList(growable: false);
    if (lrcMatches.isNotEmpty) {
      final body = line.replaceAll(lrcTimestamp, '');
      if (!elrcTag.hasMatch(body)) continue;
      for (final match in lrcMatches) {
        final position = _durationFromLrcMatch(match);
        final words = _parseElrcInlineWords(body, position);
        if (words.isNotEmpty) {
          result.putIfAbsent(position, () => words);
        }
      }
    }
  }
  return result;
}

/// 兼容部分第三方代理把歌词先按 Latin-1 转了一次或把 Unicode 转义保留为文本。
String? _normalizeMusicLyricText(String? value) {
  if (value == null || value.isEmpty) {
    return value;
  }
  var text = value.replaceAllMapped(
    RegExp(r'\\u([0-9a-fA-F]{4})'),
    (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
  );
  text = text
      .replaceAll(r'\r\n', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r');
  if (!_looksLikeMojibake(text)) {
    return text;
  }
  try {
    final bytes = _mojibakeBytes(text);
    if (bytes == null) {
      return text;
    }
    final repaired = utf8.decode(bytes, allowMalformed: false);
    if (_mojibakeMarkerCount(repaired) < _mojibakeMarkerCount(text)) {
      text = repaired;
    }
  } on FormatException {
    // 非 UTF-8 的合法拉丁歌词保持原文。
  }
  return text;
}

bool _looksLikeMojibake(String value) => _mojibakeMarkerCount(value) >= 2;

int _mojibakeMarkerCount(String value) {
  const markers = <String>{
    'Ã',
    'Â',
    'â',
    'ä',
    'æ',
    'ç',
    'å',
    'è',
    'é',
    'ï',
    '',
  };
  var count = 0;
  for (final rune in value.runes) {
    if (markers.contains(String.fromCharCode(rune))) {
      count++;
    }
  }
  return count;
}

List<int>? _mojibakeBytes(String value) {
  const cp1252 = <int, int>{
    0x20ac: 0x80,
    0x201a: 0x82,
    0x192: 0x83,
    0x201e: 0x84,
    0x2026: 0x85,
    0x2020: 0x86,
    0x2021: 0x87,
    0x2c6: 0x88,
    0x2030: 0x89,
    0x160: 0x8a,
    0x2039: 0x8b,
    0x152: 0x8c,
    0x17d: 0x8e,
    0x2018: 0x91,
    0x2019: 0x92,
    0x201c: 0x93,
    0x201d: 0x94,
    0x2022: 0x95,
    0x2013: 0x96,
    0x2014: 0x97,
    0x2dc: 0x98,
    0x2122: 0x99,
    0x161: 0x9a,
    0x203a: 0x9b,
    0x153: 0x9c,
    0x17e: 0x9e,
    0x178: 0x9f,
  };
  final bytes = <int>[];
  for (final rune in value.runes) {
    if (rune <= 0xff) {
      bytes.add(rune);
    } else {
      final mapped = cp1252[rune];
      if (mapped == null) {
        return null;
      }
      bytes.add(mapped);
    }
  }
  return bytes;
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
  final offset = start - lineStartMs;
  final span = Duration(milliseconds: duration < 0 ? 0 : duration);
  words.add(
    MusicLyricWord(
      offset: Duration(milliseconds: offset < 0 ? 0 : offset),
      duration: span,
      text: text,
    ),
  );
}

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
    final position = _durationFromLrcMatch(matches.first);
    result.putIfAbsent(position, () => text);
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
