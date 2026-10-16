import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/video/presentation/widgets/subtitle_file_decoder.dart';

/// 字幕文件名语言推断；字节解码已下沉到 `core/utils/text_file_decoder.dart`。
void main() {
  test('从文件名推断字幕语言', () {
    expect(inferSubtitleLanguage('movie.zh.srt'), 'chi');
    expect(inferSubtitleLanguage('movie.en.ass'), 'eng');
    expect(inferSubtitleLanguage('movie.srt'), 'und');
  });
}
