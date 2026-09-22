import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_playback_queue_store.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/widgets/music_platform_login.dart';
import 'package:omninest/features/music/presentation/widgets/music_platform_qr_panel.dart';

/// 平台账号窗口的交互契约：登录方式切换、验证码路径、内联二维码与断开确认。

void main() {
  late _StubMusicApi api;

  setUp(() {
    api = _StubMusicApi();
  });

  Future<ProviderContainer> pumpSheet(WidgetTester tester) async {
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
        musicPlaybackQueueStoreProvider.overrideWithValue(
          _MemoryMusicPlaybackQueueStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(body: PlatformLoginSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('登录面板只保留扫码登录，不再提供手机号与邮箱入口', (tester) async {
    await pumpSheet(tester);

    expect(find.text('手机号登录'), findsNothing);
    expect(find.text('邮箱登录'), findsNothing);
    expect(find.text('发送验证码'), findsNothing);
  });

  testWidgets('扫码默认只展示入口，点击后才申请并展示二维码', (tester) async {
    await pumpSheet(tester);

    expect(find.byType(MusicPlatformQrPanel), findsOneWidget);
    // 旧实现用 showDialog 拉独立弹层；现在二维码与登录方式选择同处一个窗口。
    expect(find.byType(Dialog), findsNothing);
    // 进入窗口不自动申请二维码会话：会话只有 5 分钟有效期，按需获取。
    expect(api.qrSessionRequests, isEmpty);
    expect(find.byKey(MusicPlatformQrPanel.qrContainerKey), findsNothing);
    expect(find.byKey(MusicPlatformQrPanel.startButtonKey), findsOneWidget);

    await tester.tap(find.byKey(MusicPlatformQrPanel.startButtonKey));
    // 轮询期间状态行带常驻进度指示，不能用 pumpAndSettle（永不静止）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.qrSessionRequests, hasLength(1));
    expect(find.byKey(MusicPlatformQrPanel.qrContainerKey), findsOneWidget);
    // 等待态以激光扫描线 + 指引行呈现（样例二维码抽屉的等待样式）。
    expect(find.text('打开网易云音乐 App，扫描此二维码。'), findsOneWidget);

    // 收尾：卸载面板触发轮询取消，再走完已排定的计时器，避免遗留 pending Timer。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('未登录时不展示断开入口', (tester) async {
    await pumpSheet(tester);

    expect(find.text('退出登录'), findsNothing);
  });

  testWidgets('已登录时断开需要二次确认', (tester) async {
    api.userInfo = const PlatformUserInfo(
      platform: 'netease',
      userId: '42',
      nickname: '听歌的人',
      vip: true,
    );
    await pumpSheet(tester);

    expect(find.text('听歌的人'), findsOneWidget);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    // 破坏性操作必须先确认，且要说清队列会被一并清理。
    expect(find.text('确认断开该账号？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(api.logoutCalls, isEmpty);
    expect(find.text('听歌的人'), findsOneWidget);
  });
}

class _MemoryMusicPlaybackQueueStore implements MusicPlaybackQueueStore {
  final Map<String, MusicPlaybackQueueSnapshot> snapshots =
      <String, MusicPlaybackQueueSnapshot>{};

  @override
  Future<MusicPlaybackQueueSnapshot?> load(String ownerId) async {
    return snapshots[ownerId];
  }

  @override
  Future<void> save(String ownerId, MusicPlaybackQueueSnapshot snapshot) async {
    snapshots[ownerId] = snapshot;
  }
}

/// 覆盖账号窗口与中心控制器所需的最小接口集合。
class _StubMusicApi implements MusicApi {
  PlatformUserInfo? userInfo;
  final List<String> logoutCalls = <String>[];
  final List<String> qrSessionRequests = <String>[];

  @override
  Future<MusicDashboard> dashboard() async => MusicDashboard.empty();

  @override
  Future<MusicPagedResult<MusicTrack>> tracks({
    int page = 0,
    int size = 100,
    String sort = 'title,asc',
  }) async => const MusicPagedResult<MusicTrack>(items: <MusicTrack>[]);

  @override
  Future<MusicPagedResult<MusicAlbum>> albums({
    int page = 0,
    int size = 100,
    String sort = 'updatedAt,desc',
  }) async => const MusicPagedResult<MusicAlbum>(
    items: <MusicAlbum>[],
    page: 0,
    size: 0,
    totalElements: 0,
  );

  @override
  Future<MusicPagedResult<MusicArtist>> artists({
    int page = 0,
    int size = 100,
    String sort = 'name,asc',
  }) async => const MusicPagedResult<MusicArtist>(
    items: <MusicArtist>[],
    page: 0,
    size: 0,
    totalElements: 0,
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
  Future<PlatformUserInfo?> platformInfo(String platform) async => userInfo;

  @override
  Future<QrLoginSession> createNeteaseQrLogin() async {
    qrSessionRequests.add('netease');
    // 1x1 PNG：测试只需合法可解码的位图，真实二维码由平台返回。
    return QrLoginSession(
      loginKey: 'key-1',
      qrImageBase64:
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );
  }

  @override
  Future<QrLoginStatus> checkNeteaseQrLogin(String key) async =>
      const QrLoginStatus(status: 'pending');

  @override
  Future<void> platformLogout(String platform) async {
    logoutCalls.add(platform);
    userInfo = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
