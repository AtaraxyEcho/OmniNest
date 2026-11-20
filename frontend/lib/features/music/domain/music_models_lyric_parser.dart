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
  final normalizedRaw = _normalizeMusicLyricText(raw);
  if (normalizedRaw == null || normalizedRaw.trim().isEmpty) {
    return const [];
  }
  final lines = <MusicLyricLine>[];
  final timestampPattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
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

  for (final rawLine in normalizedRaw.split(RegExp(r'\r?\n'))) {
    final structured = _parseNeteaseLyricJsonLine(rawLine.trim());
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
      final yrcHeader = RegExp(r'^\[(\d+),\d+\]').firstMatch(rawLine.trim());
      if (yrcHeader != null) {
        final startMs = int.tryParse(yrcHeader.group(1) ?? '');
        final text = _yrcLineText(rawLine.substring(yrcHeader.end));
        if (startMs != null && text.isNotEmpty) {
          final position = Duration(milliseconds: startMs);
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

/// 网易云逐字歌词的行级 JSON 载荷。网易云会把作词/作曲等元信息也编码成
/// `{"t":0,"c":[{"tx":"..."}]}`，不能把它当作普通文本直接交给 UI。
_StructuredMusicLyricLine? _parseNeteaseLyricJsonLine(String line) {
  if (!line.startsWith('{') && !line.startsWith('[')) {
    return null;
  }
  try {
    final decoded = jsonDecode(line);
    if (decoded is Map) {
      return _structuredLineFromJson(decoded);
    }
    // 少数代理把整段 yrc 压成一个 JSON 数组；解析首个可展示行，
    // 其余行由逐行路径处理不到，因此只在数组恰好包含一行时使用。
    if (decoded is List && decoded.length == 1 && decoded.first is Map) {
      return _structuredLineFromJson(decoded.first as Map);
    }
  } on FormatException {
    // 不是 JSON 的歌词行继续按 LRC/YRC 解析。
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
  return wordPattern
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

/// 解析逐字歌词载荷（网易云 `yrc`），返回"行起始时间 → 词列表"。
///
/// 行头为 `[行起始,行时长]`（毫秒，绝对时间），词元为 `(词起始,词时长,0)文本`，
/// 词时长按毫秒。开头的 `{"t":0,…}` 元数据行没有行头，天然被跳过；
/// 无法识别的行会被跳过；整段无法识别时返回空表，调用方退回行级显示。
Map<Duration, List<MusicLyricWord>> parseMusicLyricWords(String? raw) {
  final result = <Duration, List<MusicLyricWord>>{};
  final normalizedRaw = _normalizeMusicLyricText(raw);
  if (normalizedRaw == null || normalizedRaw.trim().isEmpty) {
    return result;
  }
  final lineHeader = RegExp(r'^\[(\d+),(\d+)\]');
  final yrcWord = RegExp(r'\((\d+),(\d+),\d+\)([^()]*)');
  for (final rawLine in normalizedRaw.split(RegExp(r'\r?\n'))) {
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

/// 兼容部分第三方代理把歌词先按 Latin-1 转了一次或把 Unicode 转义保留为文本。
/// 只在检测到明显的异常编码标记时修复，正常中文、日文和拉丁字符保持原样。
String? _normalizeMusicLyricText(String? value) {
  if (value == null || value.isEmpty) {
    return value;
  }
  var text = value.replaceAllMapped(
    RegExp(r'\\u([0-9a-fA-F]{4})'),
    (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
  );
  // 某些代理会把 JSON 内的换行再次转义，先还原成真正的歌词行分隔符。
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
    // 非 UTF-8 的合法拉丁歌词保持原文，不能用替换字符覆盖用户内容。
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
    '�',
  };
  var count = 0;
  for (final rune in value.runes) {
    if (markers.contains(String.fromCharCode(rune))) {
      count++;
    }
  }
  return count;
}

/// 将常见的 Windows-1252 标点映射回 UTF-8 字节，覆盖“ä¸­å›½”这类
/// 由代理错误解码产生的文本；其它无法确定来源的字符不参与修复。
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
