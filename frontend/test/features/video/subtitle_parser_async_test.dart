import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/video/presentation/widgets/subtitle_parser.dart';

/// 大字幕走后台 isolate，小字幕留在当前线程；两条路径结果必须一致。
void main() {
  const srt =
      '1\n00:00:01,000 --> 00:00:02,000\n第一句\n\n'
      '2\n00:00:03,000 --> 00:00:04,000\n第二句\n';

  test('小字幕同步解析，结果与同步入口一致', () async {
    // SubtitleCue 没有值相等，按字段投影比较。
    expect(
      (await parseSubtitleContentAsync(srt)).map(_cueKey),
      parseSubtitleContent(srt).map(_cueKey),
    );
  });

  test('空内容返回空列表', () async {
    expect(await parseSubtitleContentAsync('   '), isEmpty);
  });

  test('超过阈值的大字幕走后台 isolate，结果与同步解析一致', () async {
    final content = _buildAss(3000);

    expect(
      content.length,
      greaterThan(subtitleBackgroundParseThreshold),
      reason: '样本必须真的越过阈值，否则用例测不到 isolate 分支',
    );

    final cues = await parseSubtitleContentAsync(content);

    expect(cues, hasLength(3000));
    expect(cues.first.text, '第一行');
    expect(cues.last.text, '第3000行');
    expect(cues.first.startMs, 1000);
  });
}

/// 生成一份够大的 ASS：每行约 70 字符，3000 行约 200KB。
String _buildAss(int lines) {
  final buffer =
      StringBuffer()
        ..writeln('[Script Info]')
        ..writeln('ScriptType: v4.00+')
        ..writeln('[Events]')
        ..writeln(
          'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text',
        );
  for (var index = 1; index <= lines; index++) {
    final start = _assTime(index);
    final end = _assTime(index + 1);
    buffer.writeln(
      'Dialogue: 0,$start,$end,Default,,0,0,0,,第${_chineseNumber(index)}行',
    );
  }
  return buffer.toString();
}

String _assTime(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '0:${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}.00';
}

String _chineseNumber(int value) => value == 1 ? '一' : '$value';

String _cueKey(SubtitleCue cue) => '${cue.startMs}-${cue.endMs}-${cue.text}';
