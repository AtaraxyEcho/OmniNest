import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/domain/music_cover_paths.dart';
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

  test('parses netease yrc word timeline into line-relative words', () {
    // 文档样例：行头毫秒绝对时间，词元 (词起始,词时长,0)文本；
    // 16210+670=16880 恰为下一词起点，按毫秒实现。
    const yrc =
        '[16210,3460](16210,670,0)还(16880,410,0)没'
        '\n[20000,1000](20000,500,0)好';
    final lines = parseMusicLyrics(
      '[00:16.210]还没\n[00:20.00]好',
      wordLyrics: yrc,
    );

    expect(lines, hasLength(2));
    expect(lines[0].words, hasLength(2));
    expect(lines[0].words[0].offset, Duration.zero);
    expect(lines[0].words[0].duration, const Duration(milliseconds: 670));
    expect(lines[0].words[0].text, '还');
    // 词起始换算为相对行首：16880 - 16210 = 670ms。
    expect(lines[0].words[1].offset, const Duration(milliseconds: 670));
    expect(lines[0].words[1].duration, const Duration(milliseconds: 410));
    expect(lines[0].words[1].text, '没');
    expect(lines[0].wordsEnd, const Duration(milliseconds: 1080));
    expect(lines[1].words.single.text, '好');
  });

  test('yrc 行首与 LRC 行首不一致时词偏移按绝对时间重定基', () {
    // LRC 行首 16500ms、yrc 行首 16210ms：容差命中后必须把 -290ms 补回偏移，
    // 否则整块词级时间相对人声恒定滞后（逐字填充跟不上唱词）。
    const yrc = '[16210,3460](16210,670,0)还(16880,410,0)没';
    final lines = parseMusicLyrics('[00:16.500]还没', wordLyrics: yrc);

    expect(lines, hasLength(1));
    expect(lines[0].words, hasLength(2));
    // 16210 - 16500 = -290ms：负偏移保留，词元在锚点前已开唱。
    expect(lines[0].words[0].offset, const Duration(milliseconds: -290));
    // 16880 - 16500 = 380ms（未重定基时会算成 670ms）。
    expect(lines[0].words[1].offset, const Duration(milliseconds: 380));
    expect(lines[0].wordsEnd, const Duration(milliseconds: 790));
  });

  test('锚点前已在演唱的词元按已唱时长计入填充', () {
    // 负偏移若被夹到 0，行首两个词会同时起唱：锚点时刻进度算成 0，
    // 表现为填充领先人声后再错位。这里 290ms 已唱必须立刻反映在进度上。
    const yrc = '[16210,3460](16210,670,0)还(16880,410,0)没';
    final line = parseMusicLyrics('[00:16.500]还没', wordLyrics: yrc).single;

    // 总演唱时长 1080ms，锚点时刻已唱 290ms。
    expect(line.fillProgressAt(Duration.zero), closeTo(290 / 1080, 1e-9));
    // 锚点 + 380ms 时第一个词已唱完（670ms），第二个词刚起唱。
    expect(
      line.fillProgressAt(const Duration(milliseconds: 380)),
      closeTo(670 / 1080, 1e-9),
    );
    expect(line.fillProgressAt(const Duration(milliseconds: 790)), 1.0);
  });

  test(
    'yrc metadata line is skipped and unknown lines fall back to empty words',
    () {
      const yrc =
          '{"t":0,"c":[{"tx":"作词"}]}'
          '\n[1000,2000](1000,500,0)可识别'
          '\n没有行头的乱码行'
          '\n[3000,2000]()'
          '\n[abc,def](1000,500,0)坏行头';
      final wordsByLine = parseMusicLyricWords(yrc);

      // 元数据行与无法识别的行被跳过，只有合法行产生词表。
      expect(wordsByLine, hasLength(1));
      expect(wordsByLine[const Duration(seconds: 1)]!.single.text, '可识别');

      // 整段无法识别时返回空表，行级歌词不带词级数据。
      expect(parseMusicLyricWords('完全无法解析'), isEmpty);
      final lines = parseMusicLyrics('[00:01.00]Hello', wordLyrics: '完全无法解析');
      expect(lines.single.words, isEmpty);
    },
  );

  test(
    'word timeline mounts by exact timestamp first then nearest within tolerance',
    () {
      const raw = '[00:01.00]One\n[00:02.00]Two\n[00:05.00]Three';
      const yrc =
          '[1000,500](1000,500,0)A'
          '\n[2300,500](2300,500,0)B'
          '\n[9000,500](9000,500,0)C';
      final lines = parseMusicLyrics(raw, wordLyrics: yrc);

      // 精确匹配。
      expect(lines[0].words.single.text, 'A');
      // 300ms 容差内就近挂载（2300 → 2000）。
      expect(lines[1].words.single.text, 'B');
      // 超出 500ms 容差：不挂载。
      expect(lines[2].words, isEmpty);
    },
  );

  test(
    'fill progress follows completed word duration, not linear line time',
    () {
      // 行内词级仅覆盖前 0.4s：0.2s 处填充 = 0.2/0.4 = 50%，
      // 若按 1s 行时长线性插值只会是 20%——锚定"真实词时间轴"行为。
      const line = MusicLyricLine(
        position: Duration(seconds: 3),
        text: 'Lyric',
        words: [
          MusicLyricWord(
            offset: Duration.zero,
            duration: Duration(milliseconds: 400),
            text: 'Lyric',
          ),
        ],
      );
      expect(line.fillProgressAt(Duration.zero), 0.0);
      expect(line.fillProgressAt(const Duration(milliseconds: 200)), 0.5);
      expect(line.fillProgressAt(const Duration(milliseconds: 400)), 1.0);
      // 词级覆盖结束后的行内剩余时间保持满格。
      expect(line.fillProgressAt(const Duration(milliseconds: 900)), 1.0);
      // 行首之前不产生进度。
      expect(line.fillProgressAt(const Duration(milliseconds: -100)), 0.0);

      // 词间停顿不产生进度：两个词之间有空隙时，填充在空隙处保持。
      const gapped = MusicLyricLine(
        position: Duration.zero,
        text: 'AB',
        words: [
          MusicLyricWord(
            offset: Duration.zero,
            duration: Duration(milliseconds: 100),
            text: 'A',
          ),
          MusicLyricWord(
            offset: Duration(milliseconds: 500),
            duration: Duration(milliseconds: 100),
            text: 'B',
          ),
        ],
      );
      // 0.3s：第一词唱完（100/200=50%），第二词未开始——停在 50%。
      expect(gapped.fillProgressAt(const Duration(milliseconds: 300)), 0.5);
      // 0.55s：第二词唱到一半（100+50）/200 = 75%。
      expect(
        gapped.fillProgressAt(const Duration(milliseconds: 550)),
        closeTo(0.75, 0.001),
      );

      // 无词级数据：返回 null（不填充）。
      expect(
        const MusicLyricLine(
          position: Duration.zero,
          text: 'L',
        ).fillProgressAt(Duration.zero),
        isNull,
      );
    },
  );

  test('句末静默的空白词元不计入演唱时长，唱完即停在满格', () {
    const line = MusicLyricLine(
      position: Duration(seconds: 10),
      text: '唱完就停',
      words: <MusicLyricWord>[
        MusicLyricWord(
          offset: Duration.zero,
          duration: Duration(milliseconds: 500),
          text: '唱完就停',
        ),
        // 网易云 yrc 用一个长空白词元承载句后静默/间奏。
        MusicLyricWord(
          offset: Duration(milliseconds: 500),
          duration: Duration(seconds: 8),
          text: ' ',
        ),
      ],
    );
    expect(line.vocalEnd, const Duration(milliseconds: 500));
    // 唱完的瞬间即满格；其后整段间奏都保持满格，不再推进填充。
    expect(line.fillProgressAt(const Duration(milliseconds: 500)), 1.0);
    expect(line.fillProgressAt(const Duration(seconds: 8)), 1.0);

    // 整行只有空白词元：无演唱内容，vocalEnd 为 null 并回退估算时长。
    const silent = MusicLyricLine(
      position: Duration.zero,
      text: '（间奏）',
      words: <MusicLyricWord>[
        MusicLyricWord(
          offset: Duration.zero,
          duration: Duration(seconds: 8),
          text: ' ',
        ),
      ],
    );
    expect(silent.vocalEnd, isNull);
    expect(silent.fillProgressAt(const Duration(seconds: 2)), isNull);
  });

  test('补间只推进到下一个变化点，空隙内保持', () {
    const line = MusicLyricLine(
      position: Duration.zero,
      text: 'AB',
      words: <MusicLyricWord>[
        MusicLyricWord(
          offset: Duration.zero,
          duration: Duration(milliseconds: 100),
          text: 'A',
        ),
        MusicLyricWord(
          offset: Duration(seconds: 5),
          duration: Duration(milliseconds: 100),
          text: 'B',
        ),
      ],
    );
    // 1s 处落在空隙：进度停在 50%，补间目标不变，只推进到下一个词元起点。
    final gap = line.fillStateAt(const Duration(seconds: 1))!;
    expect(gap.fraction, 0.5);
    expect(gap.nextFraction, 0.5);
    expect(gap.toNextFraction, const Duration(seconds: 4));
    // 正在唱第二个词：推进到它结束处即满格。
    final singing = line.fillStateAt(const Duration(milliseconds: 5050))!;
    expect(singing.fraction, closeTo(0.75, 0.001));
    expect(singing.nextFraction, 1.0);
    expect(singing.toNextFraction, const Duration(milliseconds: 50));
    // 唱完之后不再有待推进目标。
    final done = line.fillStateAt(const Duration(seconds: 9))!;
    expect(done.fraction, 1.0);
    expect(done.nextFraction, 1.0);
    expect(done.toNextFraction, Duration.zero);
  });

  test('无词级数据时按字符数估算演唱时长，并以行间隙封顶', () {
    const line = MusicLyricLine(position: Duration.zero, text: '四个字呀');
    // 4 字 × 300ms = 1.2s，正好落在下限。
    expect(
      line.estimatedVocalSpan(const Duration(seconds: 30)),
      const Duration(milliseconds: 1200),
    );
    // 短句不低于 1.2s，长句按字数线性放大，而不是摊满整段间隙。
    expect(
      const MusicLyricLine(
        position: Duration.zero,
        text: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ).estimatedVocalSpan(const Duration(seconds: 30)),
      const Duration(seconds: 9),
    );
    expect(
      line.estimatedVocalSpan(const Duration(milliseconds: 800)),
      const Duration(milliseconds: 800),
    );
    expect(line.estimatedVocalSpan(Duration.zero), Duration.zero);
  });

  test('列表展示地址优先平台缩放图，其次本地派生缩略图', () {
    const localCover =
        '/api/v1/music/covers/7f000000-0000-0000-0000-000000000001';
    const local = MusicTrack(
      id: 'track-1',
      fileNodeId: 'file-1',
      title: 'Local',
      artistName: 'Artist',
      albumTitle: 'Album',
      format: 'flac',
      favorite: false,
      coverUrl: localCover,
    );
    expect(local.listCoverUrl, '$localCover/thumbnail');
    // 沉浸层等大尺寸surface仍取原图，派生缩略图不得替换它。
    expect(local.coverUrl, localCover);
    expect(local.coverThumbUrl, isNull);

    const platform = MusicTrack(
      id: 'track-2',
      fileNodeId: 'file-2',
      title: 'Online',
      artistName: 'Artist',
      albumTitle: 'Album',
      format: 'mp3',
      favorite: false,
      coverUrl: 'https://example.com/cover.jpg',
      coverThumbUrl: 'https://example.com/cover.jpg?paramSize=300x300',
    );
    expect(platform.listCoverUrl, platform.coverThumbUrl);

    const withoutCover = MusicTrack(
      id: 'track-3',
      fileNodeId: 'file-3',
      title: 'Bare',
      artistName: 'Artist',
      albumTitle: 'Album',
      format: 'mp3',
      favorite: false,
    );
    expect(withoutCover.listCoverUrl, isNull);

    final collectionCovers = [
      MusicAlbum(
        id: 'album-1',
        title: 'A',
        artistName: 'B',
        trackCount: 1,
        coverUrl: localCover,
      ).listCoverUrl,
      MusicPlaylist(
        id: 'playlist-1',
        name: 'P',
        playlistType: 'CUSTOM',
        trackCount: 1,
        coverUrl: localCover,
      ).listCoverUrl,
      MusicArtist(
        id: 'artist-1',
        name: 'A',
        trackCount: 1,
        albumCount: 1,
        avatarUrl: localCover,
      ).listCoverUrl,
      MusicPlayHistoryEntry(
        playableKey: 'local:1',
        title: 'T',
        artistName: 'A',
        coverUrl: localCover,
        playedAt: DateTime.utc(2026),
      ).listCoverUrl,
    ];
    for (final url in collectionCovers) {
      expect(url, '$localCover/thumbnail');
    }
  });

  test('外部地址与空值不会被拼上缩略图后缀', () {
    expect(
      musicCoverThumbnailPath('https://example.com/cover.jpg'),
      'https://example.com/cover.jpg',
    );
    expect(musicCoverThumbnailPath(''), '');
    expect(musicCoverThumbnailPath(null), isNull);
    // 展示地址可安全回流：二级缩略后缀会直接 404。
    expect(
      musicCoverThumbnailPath('/api/v1/music/covers/x/thumbnail'),
      '/api/v1/music/covers/x/thumbnail',
    );
  });
}
