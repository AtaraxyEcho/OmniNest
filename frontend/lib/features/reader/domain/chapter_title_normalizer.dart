/// 章节标题前导序号标记的归一，与后端 `ReaderTextParser.normalizeChapterTitle` 等价。
///
/// 两端必须同口径：服务端下发的显示标题要参与章节偏移校验
/// （`TxtParserService.sliceStartsWithTitle` 把本章首行施加同一归一后再比对），
/// 一份实现两种结果就会让整本书被判成偏移漂移。
library;

/// 标题前导的序号标记：第N章/节/回/卷/篇、Chapter N、裸数字加分隔符。
///
/// 捕获组取标记本身（含其后的冒号），组外再吃掉标记之间的空白。
final RegExp _tokenPattern = RegExp(
  '^((?:第\\s*[0-9〇零一二三四五六七八九十百千两]{1,8}\\s*[章节回卷篇]'
  '|[Cc][Hh][Aa][Pp][Tt][Ee][Rr]\\s+[0-9]+'
  r'|[0-9]{1,3}\s*[.、])'
  '[\\s　]*[:：]?)[\\s　]*',
);

/// 标记里的阿拉伯数字，用于与目录位次比对；中文数字不参与比对。
final RegExp _tokenDigits = RegExp(r'[0-9]+');

/// 标题尾部可能挂着的冒号分隔。
final RegExp _trailingColon = RegExp(r'[:：]$');

/// 章节标题里的一个前导序号标记。
class ChapterTitleToken {
  const ChapterTitleToken({
    required this.text,
    required this.end,
    required this.value,
  });

  /// 标记文本，已剥去首尾空白与尾随冒号。
  final String text;

  /// 标记之后在标题原文中的位置（含标记与后继空白）。
  final int end;

  /// 标记的阿拉伯数字值；中文数字或无数字为 -1。
  final int value;
}

/// 归一章标题里连续出现的序号标记。
///
/// 抓取站会在原标题前再补一个全书递增号，形成「第1章 第1章 天胡开局」或
/// 「第38章 第1章 吴兴」（卷内序号重启）。裁决口径：优先保留数值等于本章目录位次
/// 的那个标记，中文数字或都不等于位次时保留第一个；其余标记剥除，标题正文原样保留。
/// 只有一个标记时不改写，已带序号的标题也不再补号。
String normalizeChapterTitle(String rawTitle, int chapterOrdinal) {
  if (rawTitle.trim().isEmpty) {
    return rawTitle;
  }
  final tokens = <ChapterTitleToken>[];
  var cursor = 0;
  while (cursor < rawTitle.length) {
    final token = _matchToken(rawTitle, cursor);
    if (token == null) {
      break;
    }
    tokens.add(token);
    cursor = token.end;
  }
  if (tokens.length < 2) {
    return rawTitle;
  }
  var kept = tokens.first;
  for (final token in tokens) {
    if (token.value >= 0 && token.value == chapterOrdinal) {
      kept = token;
      break;
    }
  }
  final tail = rawTitle.substring(cursor).trim();
  return tail.isEmpty ? kept.text : '${kept.text} $tail';
}

ChapterTitleToken? _matchToken(String title, int from) {
  final match = _tokenPattern.matchAsPrefix(title.substring(from));
  if (match == null) {
    return null;
  }
  final text = match.group(1)!.trim().replaceAll(_trailingColon, '');
  return ChapterTitleToken(
    text: text,
    end: from + match.end,
    value: _tokenValue(text),
  );
}

int _tokenValue(String token) {
  final digits = _tokenDigits.firstMatch(token);
  if (digits != null) {
    return int.tryParse(digits.group(0)!) ?? -1;
  }
  return _chineseNumberValue(token);
}

/// 中文数字标记的取值，与后端 `ReaderTextParser.chineseNumberValue` 逐条同规则。
///
/// 不认中文数字的话，"第一回/第二回"编号的书拿不到与目录位次比对的数值，
/// 服务端也判不出序号回退，头尾的预览副本就切不出段——两端必须算出同一个数。
int _chineseNumberValue(String token) {
  var section = 0;
  var digit = 0;
  var seen = false;
  for (final char in token.runes.map(String.fromCharCode)) {
    final value = _numeralValues[char];
    if (value != null) {
      digit = value;
      seen = true;
      continue;
    }
    final unit = _unitValues[char];
    if (unit == null) {
      continue;
    }
    seen = true;
    section += (digit == 0 ? unit : digit * unit);
    digit = 0;
  }
  return seen ? section + digit : -1;
}

const Map<String, int> _numeralValues = {
  '〇': 0,
  '零': 0,
  '一': 1,
  '二': 2,
  '两': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
};

const Map<String, int> _unitValues = {'十': 10, '百': 100, '千': 1000};
