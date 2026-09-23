import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_player.dart';
import 'package:omninest/features/music/presentation/widgets/music_playback_controls.dart';

/// 不依赖原生音频引擎的播放器替身，供页面冒烟测试使用。
class _SilentMusicAudioPlayback implements MusicAudioPlayback {
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast(sync: true);

  final MusicAudioPlayerState _state = MusicAudioPlayerState(
    playing: false,
    position: const Duration(minutes: 1),
    duration: const Duration(minutes: 3),
  );

  @override
  MusicAudioPlayerState get state => _state;

  @override
  ValueListenable<MusicSpectrumFrame> get spectrum =>
      const _SilentSpectrumListenable();

  @override
  MusicAudioPlayerStreams get stream => MusicAudioPlayerStreams(
    position: _positionController.stream,
    duration: const Stream<Duration>.empty(),
    volume: const Stream<double>.empty(),
    completed: const Stream<bool>.empty(),
    log: const Stream<MusicAudioLog>.empty(),
  );

  @override
  Future<void> openUrl(String url, {required bool play}) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  MusicSpectrumFrame? readSpectrumFrame({required MusicTrack track}) => null;

  @override
  Future<void> seek(Duration position) async {}

  @override
  void setVolume(double volume) {}

  @override
  void setRelativePlaySpeed(double speed) {}

  @override
  void setSpectrumTrack(MusicTrack? track) {}

  @override
  Future<void> dispose() async {
    await _positionController.close();
  }
}

class _SilentSpectrumListenable implements ValueListenable<MusicSpectrumFrame> {
  const _SilentSpectrumListenable();

  @override
  MusicSpectrumFrame get value => MusicSpectrumFrame.silent();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// 收集当前语义树全部节点 id（调试期可用），用于断言节点未被整棵摘除。
Set<int> _semanticsIds(WidgetTester tester) {
  // 与 music_deck_shell_test 的语义断言同一取值路径：需要遍历整棵语义树，
  // 而非单个 finder，故仍走 pipelineOwner.semanticsOwner。
  // ignore: deprecated_member_use
  final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root == null) {
    return const <int>{};
  }
  final ids = <int>{};
  void visit(SemanticsNode node) {
    ids.add(node.id);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  visit(root);
  return ids;
}

void main() {
  testWidgets('进入沉浸播放页并悬停不触发 MouseTracker/布局重入', (tester) async {
    tester.view.physicalSize = const Size(1280, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appEnvironmentProvider.overrideWithValue(
            const AppEnvironment(
              apiBaseUrl: 'http://localhost',
              wsBaseUrl: 'ws://localhost',
            ),
          ),
          musicAudioPlaybackProvider.overrideWith(
            (ref) => _SilentMusicAudioPlayback(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: MusicImmersivePlayer()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // 样例居中/居右布局的 Dock 传输行含 ±10 秒快进快退。
    expect(find.byTooltip('后退 10 秒'), findsOneWidget);
    expect(find.byTooltip('前进 10 秒'), findsOneWidget);
    // 无本地播放项时不出现收藏入口（收藏命令只覆盖本地曲库）。
    expect(find.byTooltip('收藏'), findsNothing);
    expect(find.byTooltip('取消收藏'), findsNothing);

    // 用真实鼠标事件扫过卡组、歌词、底栏与空白处，覆盖 enter/exit 交错。
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    const path = <Offset>[
      Offset(640, 512),
      Offset(300, 300),
      Offset(900, 300),
      Offset(640, 950),
      Offset(20, 20),
      Offset(640, 512),
    ];
    for (final position in path) {
      final hit = HitTestResult();
      tester.binding.hitTestInView(hit, position, tester.view.viewId);
      tester.binding.dispatchEvent(pointer.hover(position), hit);
      await tester.pump();
    }
    // 均衡器动画会持续产生帧，多推几帧确认收敛。
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('小数缩放下沉浸页固定高度块不产生 RenderFlex 溢出', (tester) async {
    // DPR 2 + 逻辑 1267×1007 → 缩放系数 ≈0.983：行盒物理像素取整与固定
    // 尺寸控件（如 40px 播放键放进 40*scale 行）在此最容易触发溢出断言。
    tester.view.physicalSize = const Size(2534, 2014);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appEnvironmentProvider.overrideWithValue(
            const AppEnvironment(
              apiBaseUrl: 'http://localhost',
              wsBaseUrl: 'ws://localhost',
            ),
          ),
          musicAudioPlaybackProvider.overrideWith(
            (ref) => _SilentMusicAudioPlayback(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: MusicImmersivePlayer()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('底部 Dock 为半透明玻璃并按深浅色主题取色', (tester) async {
    Future<({Color fill, Color progress, Color title})> dockChromeOf(
      Brightness brightness,
    ) async {
      tester.view.physicalSize = const Size(1280, 1024);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appEnvironmentProvider.overrideWithValue(
              const AppEnvironment(
                apiBaseUrl: 'http://localhost',
                wsBaseUrl: 'http://localhost',
              ),
            ),
            musicAudioPlaybackProvider.overrideWith(
              (ref) => _SilentMusicAudioPlayback(),
            ),
          ],
          child: MaterialApp(
            theme:
                brightness == Brightness.light
                    ? OmniNestTheme.light()
                    : OmniNestTheme.dark(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: const Scaffold(body: MusicImmersivePlayer()),
          ),
        ),
      );
      // 主题切换经 AnimatedTheme 过渡，必须推完动画才能读到目标主题的取色。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        Theme.of(tester.element(find.byType(MusicImmersivePlayer))).brightness,
        brightness,
      );

      // 播放模式为单按钮：默认顺序档只显示列表循环图标，无随机/单曲循环图标。
      expect(find.byTooltip('顺序播放'), findsOneWidget);
      expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
      expect(find.byIcon(Icons.repeat_one_rounded), findsNothing);

      // Dock 胶囊：进度条最近的胶囊形 DecoratedBox 祖先（歌词标签同为胶囊形，
      // 但不在进度条的祖先链上）。
      final capsuleFinder = find.ancestor(
        of: find.byType(MusicPlaybackProgressBar),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(999),
        ),
      );
      final capsule = tester.widgetList<DecoratedBox>(capsuleFinder).first;
      final progress = tester.widget<MusicPlaybackProgressBar>(
        find.byType(MusicPlaybackProgressBar),
      );
      // 曲名在 Dock 与顶部曲目栏都可能出现，取 Dock 内的第一个。
      final title =
          tester
              .widgetList<Text>(
                find.descendant(of: capsuleFinder, matching: find.text('未播放')),
              )
              .first;
      return (
        fill: (capsule.decoration as BoxDecoration).color!,
        progress: progress.activeColor,
        title: title.style!.color!,
      );
    }

    final dark = await dockChromeOf(Brightness.dark);
    final light = await dockChromeOf(Brightness.light);

    // 玻璃化：胶囊填充必须是半透明，不再用接近不透明的实心底。
    expect(dark.fill.a, lessThan(0.7));
    expect(light.fill.a, lessThan(0.7));
    // 深浅色各自取色：浅色主题为亮底深字，深色主题为暗底亮字。
    expect(
      light.fill.computeLuminance(),
      greaterThan(dark.fill.computeLuminance()),
    );
    expect(
      light.title.computeLuminance(),
      lessThan(dark.title.computeLuminance()),
    );
    expect(dark.progress, Colors.white);
    expect(light.progress, isNot(Colors.white));
    expect(tester.takeException(), isNull);
  });

  testWidgets('悬停 Dock 图标不会让已有语义节点消失', (tester) async {
    // Windows 辅助功能桥的 "will not be in the tree and is not the new root"
    // 来自父节点存续期间子树被整棵摘除。Tooltip 可见时会把子节点包成
    // RawTooltip（widget 类型变化即重挂载），因此这里直接断言：悬停弹出
    // 提示前后，已存在的语义节点 id 不会被移除。
    tester.view.physicalSize = const Size(1280, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final player = _SilentMusicAudioPlayback();
    addTearDown(player.dispose);

    final container = ProviderContainer.test(
      overrides: [
        appEnvironmentProvider.overrideWithValue(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost',
            wsBaseUrl: 'http://localhost',
          ),
        ),
        musicAudioPlaybackProvider.overrideWith((ref) => player),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: MusicImmersivePlayer()),
        ),
      ),
    );
    final handle = tester.ensureSemantics();
    await tester.pump();
    await tester.pump();

    final before = _semanticsIds(tester);
    expect(before, isNotEmpty);

    final target = tester.getCenter(find.byIcon(Icons.skip_next_rounded));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final hit = HitTestResult();
    tester.binding.hitTestInView(hit, target, tester.view.viewId);
    tester.binding.dispatchEvent(pointer.hover(target), hit);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      before.difference(_semanticsIds(tester)),
      isEmpty,
      reason: '悬停提示不应让既有语义节点从树上消失',
    );

    // 音量面板经 OverlayPortal 开合：关闭时移除的只能是面板自身节点。
    final volumeTarget = tester.getCenter(find.byIcon(Icons.volume_up_rounded));
    final volumeHit = HitTestResult();
    tester.binding.hitTestInView(volumeHit, volumeTarget, tester.view.viewId);
    tester.binding.dispatchEvent(pointer.hover(volumeTarget), volumeHit);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      before.difference(_semanticsIds(tester)),
      isEmpty,
      reason: '音量面板展开不应让既有语义节点从树上消失',
    );
    // 鼠标移开触发面板收起（用远端 hover 事件产生 exit，而不是移出指针）。
    const away = Offset(20, 20);
    final awayHit = HitTestResult();
    tester.binding.hitTestInView(awayHit, away, tester.view.viewId);
    tester.binding.dispatchEvent(pointer.hover(away), awayHit);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      before.difference(_semanticsIds(tester)),
      isEmpty,
      reason: '音量面板收起不应让既有语义节点从树上消失',
    );

    handle.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dock 切到随机后点下一首按洗牌序推进', (tester) async {
    tester.view.physicalSize = const Size(1280, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final player = _SilentMusicAudioPlayback();
    addTearDown(player.dispose);
    final container = ProviderContainer.test(
      overrides: [
        appEnvironmentProvider.overrideWithValue(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost',
            wsBaseUrl: 'http://localhost',
          ),
        ),
        musicApiProvider.overrideWithValue(_FourTrackMusicApi()),
        musicAudioPlaybackProvider.overrideWith((ref) => player),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);
    await controller.playItems(_FourTrackMusicApi.items, startIndex: 0);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: MusicImmersivePlayer()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('顺序播放'), findsOneWidget);

    controller.random = math.Random(11);
    await tester.tap(find.byTooltip('顺序播放'));
    await tester.pump();
    expect(find.byTooltip('随机播放'), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);

    // 与实现同构的 Fisher-Yates：期望下一首来自洗牌序队头而非队列后继。
    final expected = _shuffledRestInSeedOrder(math.Random(11));
    await tester.tap(find.byTooltip('下一首'));
    await tester.pump();
    await tester.pump();

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.playMode, MusicPlayMode.shuffle);
    expect(state.currentItem?.playableKey, expected.first);
    expect(tester.takeException(), isNull);
  });
}

/// 与 `MusicCenterController._startShuffleRound` 同构的洗牌序推导。
List<String> _shuffledRestInSeedOrder(math.Random random) {
  final keys = <String>['local:track-2', 'local:track-3', 'local:track-4'];
  for (var i = keys.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final swapped = keys[i];
    keys[i] = keys[j];
    keys[j] = swapped;
  }
  return keys;
}

/// 四首本地曲目的最小后端替身：够播放队列推进与播放计划解析。
class _FourTrackMusicApi implements MusicApi {
  static final List<MusicPlayableItem> items =
      List<MusicPlayableItem>.unmodifiable(
        libraryTracks.map(MusicPlayableItem.local),
      );

  static const List<MusicTrack> libraryTracks = <MusicTrack>[
    MusicTrack(
      id: 'track-1',
      fileNodeId: 'file-1',
      title: 'Track One',
      artistName: 'Omni Band',
      albumTitle: 'Album',
      format: 'mp3',
      favorite: false,
    ),
    MusicTrack(
      id: 'track-2',
      fileNodeId: 'file-2',
      title: 'Track Two',
      artistName: 'Omni Band',
      albumTitle: 'Album',
      format: 'mp3',
      favorite: false,
    ),
    MusicTrack(
      id: 'track-3',
      fileNodeId: 'file-3',
      title: 'Track Three',
      artistName: 'Omni Band',
      albumTitle: 'Album',
      format: 'mp3',
      favorite: false,
    ),
    MusicTrack(
      id: 'track-4',
      fileNodeId: 'file-4',
      title: 'Track Four',
      artistName: 'Omni Band',
      albumTitle: 'Album',
      format: 'mp3',
      favorite: false,
    ),
  ];

  @override
  Future<MusicDashboard> dashboard() async =>
      MusicDashboard.fromJson(const <String, dynamic>{});

  @override
  Future<MusicPagedResult<MusicTrack>> tracks({
    int page = 0,
    int size = 100,
    String sort = 'title,asc',
  }) async => MusicPagedResult<MusicTrack>(
    items: libraryTracks,
    page: 0,
    size: size,
    totalElements: libraryTracks.length,
  );

  @override
  Future<MusicPagedResult<MusicAlbum>> albums({
    int page = 0,
    int size = 100,
    String sort = 'updatedAt,desc',
  }) async => MusicPagedResult<MusicAlbum>(
    items: const <MusicAlbum>[],
    page: 0,
    size: size,
  );

  @override
  Future<MusicPagedResult<MusicArtist>> artists({
    int page = 0,
    int size = 100,
    String sort = 'name,asc',
  }) async => MusicPagedResult<MusicArtist>(
    items: const <MusicArtist>[],
    page: 0,
    size: size,
  );

  @override
  Future<List<MusicPlaylist>> playlists() async => const <MusicPlaylist>[];

  @override
  Future<List<MusicRecentEntry>> recentItems() async =>
      const <MusicRecentEntry>[];

  @override
  Future<MusicTrack?> lastPlayed() async => null;

  @override
  Future<MusicPlaybackQueueSnapshot> playbackQueue() async =>
      const MusicPlaybackQueueSnapshot();

  @override
  Future<MusicPlaybackQueueSnapshot> savePlaybackQueue(
    MusicPlaybackQueueSnapshot snapshot,
  ) async => snapshot;

  @override
  Future<MusicPlaybackPlan> playbackPlan(String trackId) async =>
      MusicPlaybackPlan(trackId: trackId, url: 'https://example/$trackId.mp3');

  @override
  Future<PlatformUserInfo?> platformInfo(String platform) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
