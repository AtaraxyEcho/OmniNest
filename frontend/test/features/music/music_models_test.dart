import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/domain/music_models.dart';

void main() {
  test('parses lrc lyrics and keeps timestamps ordered', () {
    final lines = parseMusicLyrics('''
[00:10.00]First line
[00:05.50]Intro
[ar:Unknown Artist]
[00:10.00][00:20.00]Hook
''');

    expect(lines, hasLength(4));
    expect(lines[0].position, const Duration(seconds: 5, milliseconds: 500));
    expect(lines[0].text, 'Intro');
    expect(lines[1].position, const Duration(seconds: 10));
    expect(lines[1].text, 'First line');
    expect(lines[2].position, const Duration(seconds: 10));
    expect(lines[2].text, 'Hook');
    expect(lines[3].position, const Duration(seconds: 20));
    expect(lines[3].text, 'Hook');
  });

  test('lyrics translation aligns by nearest earlier timestamp', () {
    const raw = '[00:05.00]Hello\n[00:10.00]World';
    const translation = '[00:05.00]你好\n[00:10.20]世界';
    final lines = parseMusicLyrics(raw, translation: translation);

    expect(lines, hasLength(2));
    expect(lines[0].translation, '你好');
    expect(lines[1].translation, '世界');
  });

  test('lyrics without matching translation leave lines untranslated', () {
    const raw = '[00:05.00]Hello';
    final lines = parseMusicLyrics(raw, translation: '[00:30.00]迟到译文');
    expect(lines.single.translation, isNull);
  });

  test('plain text translation never aligns and stays null', () {
    const raw = '[00:05.00]Hello';
    final lines = parseMusicLyrics(raw, translation: '纯文本译文');
    expect(lines.single.translation, isNull);
  });

  test('music track exposes parsed lyric lines', () {
    const track = MusicTrack(
      id: 'track-1',
      fileNodeId: 'file-1',
      title: 'Night Drive',
      artistName: 'Omni Band',
      albumTitle: 'Unknown Album',
      format: 'flac',
      favorite: false,
      lyricsRaw: '[00:01.00]Hello',
    );

    expect(track.lyricLines, hasLength(1));
    expect(track.lyricLines.single.position, const Duration(seconds: 1));
    expect(track.lyricLines.single.text, 'Hello');
  });

  test('music track parses genre from json', () {
    const track = MusicTrack(
      id: 't',
      fileNodeId: 'f',
      title: 'T',
      artistName: 'A',
      albumTitle: 'Al',
      format: 'mp3',
      favorite: false,
      genre: 'Pop',
    );
    expect(track.genre, 'Pop');
  });
}
