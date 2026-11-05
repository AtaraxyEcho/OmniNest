// 字幕解析工具 — 支持 WebVTT / SRT / ASS 格式

import 'package:flutter/foundation.dart';

/// 超过该字符数的字幕放到后台 isolate 解析。
///
/// ASS 整集按行展开后有上万条 cue，主线程一次跑完会吃掉整帧预算，
/// 表现为导入字幕时画面卡一下；小字幕同步解析，省掉 isolate 启动开销。
const int subtitleBackgroundParseThreshold = 64 * 1024;

class SubtitleCue {
  const SubtitleCue({
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  final int startMs;
  final int endMs;
  final String text;
}

/// 解析字幕内容，自动识别 WebVTT / SRT / ASS 格式
List<SubtitleCue> parseSubtitleContent(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return [];
  // ASS/SSA 格式：[Script Info] 开头
  if (trimmed.contains('[Script Info]') || trimmed.contains('[V4+ Styles]')) {
    return parseASS(trimmed);
  }
  // SRT 格式：纯数字序号开头 + 逗号分隔的时间码
  // WebVTT 格式：WEBVTT 开头 或 --> 分隔的时间码
  return parseWebVTTOrSRT(trimmed);
}

/// 按体积选择解析线程：大字幕走 [compute]，小字幕留在当前线程。
///
/// 返回的 [SubtitleCue] 只含值字段，可跨 isolate 传递。
Future<List<SubtitleCue>> parseSubtitleContentAsync(String content) async {
  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    return const [];
  }
  if (trimmed.length <= subtitleBackgroundParseThreshold) {
    return parseSubtitleContent(trimmed);
  }
  return compute(parseSubtitleContent, trimmed);
}

/// 解析 WebVTT / SRT 格式（两者结构几乎一致，仅时间码分隔符不同）
List<SubtitleCue> parseWebVTTOrSRT(String content) {
  final cues = <SubtitleCue>[];
  final blocks = content.split(RegExp(r'\r?\n\r?\n'));
  for (final block in blocks) {
    final lines = block.trim().split('\n');
    if (lines.length < 2) continue;
    // 查找时间码行（包含 "-->" 的行）
    int timeLineIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains('-->')) {
        timeLineIndex = i;
        break;
      }
    }
    if (timeLineIndex < 0) continue;
    final timeParts = lines[timeLineIndex].split('-->');
    if (timeParts.length != 2) continue;
    final startMs = parseSubtitleTime(timeParts[0].trim());
    final endMs = parseSubtitleTime(timeParts[1].trim());
    if (startMs < 0 || endMs < 0) continue;
    // 文本行：跳过时间码之后的内容，去除 HTML/VTT 标签
    final textLines = lines.sublist(timeLineIndex + 1);
    final text = textLines
        .map((l) => l.replaceAll(RegExp(r'<[^>]+>'), '').trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
    if (text.isNotEmpty) {
      cues.add(SubtitleCue(startMs: startMs, endMs: endMs, text: text));
    }
  }
  return cues;
}

/// 解析 ASS/SSA 格式字幕
List<SubtitleCue> parseASS(String content) {
  final cues = <SubtitleCue>[];
  final lines = content.split(RegExp(r'\r?\n'));
  // 找到 [Events] 段
  int eventsStart = -1;
  String format = 'Start,End,Style,Name,MarginL,MarginR,MarginV,Effect,Text';
  for (int i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    if (trimmed == '[Events]') {
      eventsStart = i;
    } else if (eventsStart >= 0 && trimmed.startsWith('Format:')) {
      format = trimmed.substring(7).trim();
    }
  }
  if (eventsStart < 0) return cues;
  final formatFields =
      format.split(',').map((f) => f.trim().toLowerCase()).toList();
  final startIndex = formatFields.indexOf('start');
  final endIndex = formatFields.indexOf('end');
  final textIndex = formatFields.indexOf('text');
  if (startIndex < 0 || endIndex < 0 || textIndex < 0) return cues;
  for (int i = eventsStart + 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (!line.startsWith('Dialogue:')) continue;
    final data = line.substring(10).trim();
    final parts = <String>[];
    int depth = 0;
    int lastSplit = 0;
    for (int j = 0; j < data.length; j++) {
      if (data[j] == '(') depth++;
      if (data[j] == ')') depth--;
      if (data[j] == ',' && depth == 0) {
        parts.add(data.substring(lastSplit, j));
        lastSplit = j + 1;
      }
    }
    parts.add(data.substring(lastSplit));
    if (parts.length <= textIndex) continue;
    final startMs = parseASSTime(parts[startIndex].trim());
    final endMs = parseASSTime(parts[endIndex].trim());
    if (startMs < 0 || endMs < 0) continue;
    // 去除 ASS 样式标签 {\xxx}，替换 \N 为换行
    final rawText = parts.sublist(textIndex).join(',').trim();
    final text =
        rawText
            .replaceAll(RegExp(r'\{[^}]*\}'), '')
            .replaceAll('\\N', '\n')
            .replaceAll('\\n', '\n')
            .trim();
    if (text.isNotEmpty) {
      cues.add(SubtitleCue(startMs: startMs, endMs: endMs, text: text));
    }
  }
  return cues;
}

/// 解析字幕时间码，支持 WebVTT 点分隔（HH:MM:SS.mmm）和 SRT 逗号分隔（HH:MM:SS,mmm）
int parseSubtitleTime(String time) {
  final normalized = time.replaceAll(',', '.');
  final parts = normalized.split(':');
  if (parts.length < 2 || parts.length > 3) return -1;
  try {
    double seconds;
    if (parts.length == 3) {
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      seconds = double.parse(parts[2]);
      return ((h * 3600 + m * 60) * 1000 + (seconds * 1000)).round();
    } else {
      final m = int.parse(parts[0]);
      seconds = double.parse(parts[1]);
      return (m * 60 * 1000 + (seconds * 1000)).round();
    }
  } catch (_) {
    return -1;
  }
}

/// 解析 ASS 时间码（H:MM:SS.cc，centisecond 精度）
int parseASSTime(String time) {
  final parts = time.split(':');
  if (parts.length != 3) return -1;
  try {
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final secParts = parts[2].split('.');
    final s = int.parse(secParts[0]);
    final cs = secParts.length > 1 ? int.parse(secParts[1]) : 0;
    return (h * 3600 + m * 60 + s) * 1000 + cs * 10;
  } catch (_) {
    return -1;
  }
}
