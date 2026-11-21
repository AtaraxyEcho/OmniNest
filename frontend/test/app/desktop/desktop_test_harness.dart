/// 桌面视图测试的共用装配：种子数据、网络封面替身与主题包装。
///
/// 桌面首页与壳层跨六个模块取数，逐个搭真实 repository 既慢又脆；
/// 这里只在**门面 provider** 这一层注入种子，被测代码走的仍是生产路径。
library;

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/environment_providers.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/theme/desktop/desktop_palette.dart';
import 'package:omninest/app/theme/desktop/desktop_theme.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/core/storage/local_database_provider.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/features/admin/application/admin_console_access_provider.dart';
import 'package:omninest/features/files/file_dashboard.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/features/photos/photo_dashboard.dart';
import 'package:omninest/features/photos/domain/photo.dart' show PhotoAlbumPage;
import 'package:omninest/features/photos/domain/photo_repository.dart';
import 'package:omninest/features/portal/portal_weather.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';
import 'package:omninest/features/reader/application/reader_controller.dart'
    show ReaderCenterController, ReaderCenterState;
import 'package:omninest/features/tasks/application/task_controller.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';
import 'package:omninest/features/video/video_dashboard.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart'
    show MovieStats;
import 'package:omninest/features/reader/domain/reader_dashboard.dart'
    show ReaderOverview;
import 'package:omninest/features/music/domain/music_models.dart'
    show MusicAlbum, MusicDashboard, MusicPlaylist, MusicTrack;

const Size kDesktopViewport = Size(1600, 1000);

class _SeededPhotoController extends PhotoDashboardController {
  @override
  Future<PhotoDashboard> build() async => seededPhotoDashboard;
}

/// 空库分支用：照片门面返回空概览。
class EmptyPhotoController extends PhotoDashboardController {
  @override
  Future<PhotoDashboard> build() async => PhotoDashboard.empty();
}

/// 照片分页仓储替身：只实现桌面页会读的两条列表，其余调用直接失败，
/// 避免把未种子的接口伪装成"空数据"。
class _SeededPhotoRepository implements PhotoRepository {
  _SeededPhotoRepository({required this.empty});

  final bool empty;

  PhotoPage _page(List<PhotoItem> items) =>
      empty
          ? PhotoPage.empty()
          : PhotoPage(
            items: items,
            page: 0,
            size: 50,
            totalElements: items.length,
            totalPages: 1,
          );

  @override
  Future<PhotoDashboard> dashboard() async =>
      empty ? PhotoDashboard.empty() : seededPhotoDashboard;

  @override
  Future<PhotoPage> listTrash({int page = 0, int size = 50}) async =>
      PhotoPage.empty();

  @override
  Future<PhotoAlbumPage> listAlbumsPage({int page = 0, int size = 50}) async =>
      const PhotoAlbumPage(
        items: <PhotoAlbum>[],
        page: 0,
        size: 50,
        totalElements: 0,
        totalPages: 1,
      );

  @override
  Future<PhotoPage> listPhotos({
    int page = 0,
    String? query,
    int size = 50,
    String sort = 'dateTaken,desc',
  }) async => _page(seededPhotoDashboard.recentPhotos);

  @override
  Future<PhotoPage> listFavorites({
    int page = 0,
    String? query,
    int size = 50,
    String sort = 'dateTaken,desc',
  }) async => _page(seededPhotoDashboard.favoritePhotos);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 桌面阅读页只读 `readerCenterControllerProvider`（书库/书架/统计共用），
/// 单独种 dashboard 不够，这里直接给成品 state。
class _SeededReaderCenter extends ReaderCenterController {
  @override
  Future<ReaderCenterState> build() async => ReaderCenterState(
    dashboard: seededReaderDashboard,
    items: seededReaderDashboard.recentItems,
    searchQuery: '',
  );
}

class _EmptyReaderCenter extends ReaderCenterController {
  @override
  Future<ReaderCenterState> build() async => ReaderCenterState.empty();
}

class _SeededNotifications extends NotificationController {
  @override
  NotificationState build() => NotificationState(
    items: seededNotifications,
    total: seededNotifications.length,
    allTotal: seededNotifications.length,
  );

  @override
  Future<void> load({int page = 0, int size = 20}) async {}

  // 真实实现会把已读推到服务端并就地改内存态；桩里省掉网络，但保留状态
  // 变更，否则「点行只标已读」「Clear all 不删记录」这两条语义测不出来。
  @override
  Future<void> markRead(String id) async {
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.id == id) item.copyWith(read: true) else item,
      ],
    );
    _syncUnread();
  }

  @override
  Future<void> markAllRead() async {
    state = state.copyWith(
      items: [for (final item in state.items) item.copyWith(read: true)],
    );
    _syncUnread();
  }

  @override
  Future<void> clearAll() async {
    state = NotificationState(items: const [], total: 0);
    _syncUnread();
  }

  void _syncUnread() {
    ref
        .read(unreadCountProvider.notifier)
        .set(state.items.where((item) => !item.read).length);
  }
}

class _SeededTasks extends TaskListNotifier {
  @override
  List<TaskRecord> build() => seededTasks;

  @override
  Future<void> load() async {}
}

class _SeededSession extends AuthSessionNotifier {
  @override
  Future<AuthSessionState> build() async => AuthSessionState(
    user: UserProfile(
      id: 'u-1',
      username: 'mira',
      displayName: 'Mira Han',
      role: 'SUPER_ADMIN',
      roles: const {'SUPER_ADMIN'},
    ),
  );
}

class _SeededUnread extends UnreadCountNotifier {
  @override
  int build() => seededNotifications.where((item) => !item.read).length;

  @override
  Future<void> refresh() async {}
}

/// 音乐中心状态：桌面播放条与队列坞读它取时长/收藏/播放模式/完整队列。
class SeededMusicCenter extends MusicCenterController {
  @override
  Future<MusicCenterState> build() async => MusicCenterState(
    dashboard: MusicDashboard.empty(),
    // 曲库给两首：桌面音乐页的表格、收藏筛选与首页轨道都靠它。
    tracks: [seededLocalTrack, seededSecondTrack],
    albums: const [
      MusicAlbum(
        id: 'al-1',
        title: 'Blue Hours',
        artistName: 'Aoi Trio',
        trackCount: 4,
      ),
    ],
    playlists: const [
      MusicPlaylist(
        id: 'pl-1',
        name: 'Late night',
        playlistType: 'CUSTOM',
        trackCount: 12,
      ),
    ],
    artists: const [],
    currentItem: MusicPlayableItem.local(seededLocalTrack),
    isPlaying: true,
    playbackItems: [MusicPlayableItem.local(seededLocalTrack)],
    playbackIndex: 0,
  );
}

class _SeededTimeline implements MusicPortalPlaybackTimeline {
  @override
  Duration get position => const Duration(seconds: 96);

  @override
  Stream<Duration> get positionStream =>
      Stream<Duration>.value(const Duration(seconds: 96));

  @override
  Future<void> seek(Duration position) async {}
}

class _NoopMusicActions implements MusicPortalActions {
  @override
  Future<void> refresh() async {}
  @override
  Future<void> togglePlayback() async {}
  @override
  Future<void> previousTrack() async {}
  @override
  Future<void> nextTrack() async {}
  @override
  Future<void> playRecentTrack(String trackId) async {}
  @override
  Future<void> playTrackById(String trackId) async {}
  @override
  Future<void> playQueueAt(int index) async {}
  @override
  Future<void> playAlbum(MusicAlbum album) async {}
  @override
  Future<void> syncPlayback() async {}
}

const MovieVideoItem seededMovie = MovieVideoItem(
  id: 'v-1',
  fileNodeId: 'f-1',
  // 电影条目必须带 movieId：详情编辑抽屉用它区分电影与单集表单
  // （`_isMovie => item.movieId != null`）。
  movieId: 'm-1',
  mediaType: 'MOVIE',
  title: 'Aperture',
  metadataStatus: 'MATCHED',
  nfoStatus: 'PRESENT',
  updatedAt: null,
  metadata: {},
  posterUrl: 'https://example.test/aperture-poster.jpg',
  backdropUrl: 'https://example.test/aperture-backdrop.jpg',
  runtimeSeconds: 6360,
  genres: ['Drama', 'Mystery'],
  rating: 8.4,
  overview:
      'A photographer returns to the coastline she left behind, and finds the '
      'light has been waiting for her all along.',
);

const MovieContinueWatching seededResume = MovieContinueWatching(
  id: 'v-1',
  title: 'Aperture',
  positionSeconds: 2280,
  durationSeconds: 6360,
  progressPercent: 36,
  posterUrl: 'https://example.test/aperture-backdrop.jpg',
  mediaType: 'MOVIE',
);

final MovieDashboard seededMovieDashboard = MovieDashboard(
  stats: const MovieStats(
    movieCount: 128,
    episodeCount: 412,
    seriesCount: 24,
    scrapeFailedCount: 0,
    continueWatchingCount: 3,
  ),
  recentlyAdded: const [seededMovie],
  continueWatching: const [seededResume],
  series: const [],
);

final PhotoItem seededPhoto = PhotoItem(
  id: 'p-1',
  fileNodeId: 'f-9',
  title: 'Golden hour',
  format: 'JPEG',
  fileSize: 8400000,
  width: 6000,
  height: 4000,
  coverUrl: 'https://example.test/photo-1.jpg',
  metadataStatus: 'MATCHED',
  createdAt: null,
  favorite: true,
  cameraMake: 'Fujifilm',
  cameraModel: 'X-T5',
);

final PhotoDashboard seededPhotoDashboard = PhotoDashboard(
  totalPhotos: 4382,
  totalAlbums: 18,
  totalFavorites: 96,
  recentPhotos: List.generate(
    7,
    (index) => PhotoItem(
      id: 'p-$index',
      fileNodeId: 'f-$index',
      title: 'Frame ${index + 1}',
      format: 'JPEG',
      fileSize: 8400000,
      width: index.isEven ? 6000 : 4000,
      height: index.isEven ? 4000 : 6000,
      coverUrl: 'https://example.test/photo-$index.jpg',
      metadataStatus: 'MATCHED',
      createdAt: null,
      favorite: index == 0,
    ),
  ),
  favoritePhotos: [seededPhoto],
);

final ReaderItem seededBook = ReaderItem(
  id: 'b-1',
  title: 'The Quiet Arrival',
  authorName: 'Ines Aoki',
  itemType: 'EPUB',
  contentKind: 'TEXT',
  progressPercent: 64,
  currentChapterTitle: 'Kyoto',
  updatedAt: null,
  createdAt: null,
  description:
      'Essays on staying still while everything around you keeps moving.',
);

final ReaderDashboard seededReaderDashboard = ReaderDashboard(
  overview: ReaderOverview(
    totalItems: 42,
    continueCount: 9,
    // 14 天柱图需要真实序列，否则 Reader 总览右侧面板只剩四张卡。
    dailyReading: [
      for (var i = 0; i < 14; i++)
        ReaderDailyReading(
          date: '2026-11-${(i + 1).toString().padLeft(2, '0')}',
          minutes: 12 + (i * 7) % 23,
        ),
    ],
  ),
  continueReading: [seededBook],
  recentItems: [seededBook],
);

const FileStorageStats seededStorage = FileStorageStats(
  totalFiles: 52418,
  totalFolders: 1204,
  usedBytes: 73443901440,
  quotaBytes: 107374182400,
  quotaStatus: 'OK',
  typeDistribution: [],
);

final List<FileNode> seededFiles = List.generate(
  5,
  (index) => FileNode(
    id: 'n-$index',
    name:
        const [
          'Field notes.pdf',
          'Harbour at dusk.jpg',
          'Aperture.2160p.mkv',
          'Evening drift.flac',
          'Reading list.txt',
        ][index],
    isFolder: false,
    parentId: null,
    updatedAt: null,
    nodeType: const ['DOCUMENT', 'IMAGE', 'VIDEO', 'AUDIO', 'DOCUMENT'][index],
    normalizedPath: '/OmniCloud/file-$index',
    sizeBytes: const [1200000, 8400000, 19700000000, 42000000, 6200][index],
    spaceType: SpaceType.personal,
  ),
);

final List<MusicPortalTrack> seededTracks = List.generate(
  4,
  (index) => MusicPortalTrack(
    id: 't-$index',
    title:
        const [
          'Evening Drift',
          'Slow Harbour',
          'Paper Lanterns',
          'Northbound',
        ][index],
    artistName: const ['Aoi Trio', 'Lena Marsh', 'Kite & Co', 'Sora'][index],
    albumTitle: 'Blue Hours',
    coverUrl: 'https://example.test/cover-$index.jpg',
    lyrics: const [],
  ),
);

final MusicTrack seededLocalTrack = MusicTrack(
  id: 't-0',
  fileNodeId: 'f-a',
  title: 'Evening Drift',
  artistName: 'Aoi Trio',
  albumTitle: 'Blue Hours',
  format: 'FLAC',
  favorite: true,
  durationSeconds: 254,
  coverUrl: 'https://example.test/cover-0.jpg',
);

final MusicTrack seededSecondTrack = const MusicTrack(
  id: 't-1',
  fileNodeId: 'f-b',
  title: 'Slow Harbour',
  artistName: 'Lena Marsh',
  albumTitle: 'Blue Hours',
  format: 'FLAC',
  favorite: false,
  durationSeconds: 198,
  coverUrl: 'https://example.test/cover-1.jpg',
);

final MusicPortalSnapshot seededMusicSnapshot = MusicPortalSnapshot(
  featuredTrack: seededTracks.first,
  featuredAlbum: null,
  activeTrack: seededTracks.first,
  queuePreview: seededTracks,
  recentTracks: seededTracks,
  recentPlayCount: 128,
  trackCount: 128,
  weekListeningSeconds: 12 * 3600,
  itemsAddedToday: 42,
  isPlaying: true,
);

final List<NotificationDto> seededNotifications = [
  NotificationDto(
    id: 'nt-1',
    type: 'PHOTO_IMPORT',
    title: 'Import finished',
    message: '42 photos → Golden hour',
    read: false,
    createdAt: DateTime(2026, 11, 14, 9, 12),
  ),
  NotificationDto(
    id: 'nt-2',
    type: 'TRANSCODE',
    title: 'Transcode ready',
    message: 'Aperture · 4K HDR',
    read: false,
    createdAt: DateTime(2026, 11, 14, 8, 40),
  ),
  NotificationDto(
    id: 'nt-3',
    type: 'SHARE',
    title: 'Share opened',
    message: 'A quiet weekend by the water',
    read: true,
    createdAt: DateTime(2026, 11, 13, 20, 5),
  ),
];

final List<TaskRecord> seededTasks = [
  TaskRecord(
    id: 'k-1',
    taskType: 'THUMBNAILS',
    status: 'RUNNING',
    progress: 64,
    retryCount: 0,
    maxRetries: 3,
    createdAt: DateTime(2026, 11, 14, 9, 0),
  ),
  TaskRecord(
    id: 'k-2',
    taskType: 'MUSIC_SCAN',
    status: 'FAILED',
    progress: 0,
    errorMessage: 'Scanner could not read /Music/incoming',
    retryCount: 1,
    maxRetries: 3,
    createdAt: DateTime(2026, 11, 14, 8, 30),
  ),
];

const WeatherData seededWeather = WeatherData(
  temp: 18,
  feelsLike: 16,
  tempMax: 21,
  tempMin: 12,
  text: 'Partly cloudy',
  icon: '101',
  humidity: '62',
  windSpeed: '11',
  windDir: 'NE',
  pressure: '1013',
  visibility: '16',
  uvIndex: 3,
  sunrise: '06:12',
  sunset: '17:24',
  aqi: 42,
  pm2p5: 12,
  aqiCategory: 'Good',
  updateTime: '09:20',
  locationName: 'Hangzhou',
);

/// 门面层的种子注入。被测 widget 仍走生产 provider 读取路径。
///
/// [empty] 切到空库分支：同一容器内不允许重复 override 同一 provider，
/// 因此空态在这里替换而不是让调用方追加。
List<Override> desktopSeedOverrides({
  bool empty = false,
  AuthSessionNotifier Function()? session,
  MusicPortalActions? musicActions,
  ReaderDashboard? readerDashboard,
}) => [
  // 壁纸仓储会读本地库；测试进程没有 path_provider，改用内存库，
  // 否则长帧用例（视觉基线）会在打开连接时抛 MissingPluginException。
  localDatabaseProvider.overrideWith((ref) {
    final database = LocalDatabase(NativeDatabase.memory());
    ref.onDispose(database.close);
    return database;
  }),
  movieDashboardProvider.overrideWith(
    (ref) async => empty ? MovieDashboard.empty() : seededMovieDashboard,
  ),
  photoDashboardProvider.overrideWith(
    empty ? EmptyPhotoController.new : _SeededPhotoController.new,
  ),
  // 桌面相册页按日分组读列表与收藏；分页控制器已改为类，直接在仓储层
  // 注入成品页，生产控制器照常走 build/loadMore 路径。
  photoRepositoryProvider.overrideWithValue(
    _SeededPhotoRepository(empty: empty),
  ),
  readerCenterControllerProvider.overrideWith(
    empty ? _EmptyReaderCenter.new : _SeededReaderCenter.new,
  ),
  photoAlbumsProvider.overrideWith(
    (ref) async =>
        empty
            ? const <PhotoAlbum>[]
            : const <PhotoAlbum>[
              PhotoAlbum(
                id: 'al-1',
                name: 'Golden hour',
                description: '',
                photoCount: 42,
                createdAt: null,
                updatedAt: null,
              ),
            ],
  ),
  readerDashboardProvider.overrideWith(
    (ref) async =>
        readerDashboard ??
        (empty
            ? const ReaderDashboard(
              overview: ReaderOverview(totalItems: 0, continueCount: 0),
              continueReading: [],
              recentItems: [],
            )
            : seededReaderDashboard),
  ),
  fileStorageStatsProvider.overrideWith((ref) async => seededStorage),
  fileRecentEntriesProvider.overrideWith(
    (ref) async => empty ? const <FileNode>[] : seededFiles,
  ),
  realtimeWeatherProvider.overrideWith((ref) async => seededWeather),
  musicPortalSnapshotProvider.overrideWith(
    (ref) => AsyncData(seededMusicSnapshot),
  ),
  musicPortalPlaybackTimelineProvider.overrideWithValue(_SeededTimeline()),
  musicPortalActionsProvider.overrideWithValue(
    musicActions ?? _NoopMusicActions(),
  ),
  musicCenterControllerProvider.overrideWith(SeededMusicCenter.new),
  notificationControllerProvider.overrideWith(_SeededNotifications.new),
  unreadCountProvider.overrideWith(_SeededUnread.new),
  taskListProvider.overrideWith(_SeededTasks.new),
  activeTaskSummaryProvider.overrideWith(
    (ref) async => const ActiveTaskSummary(activeCount: 1, failedCount: 1),
  ),
  authSessionProvider.overrideWith(session ?? _SeededSession.new),
  canAccessAdminConsoleProvider.overrideWithValue(true),
  appOnlineStatusProvider.overrideWith((ref) => Stream<bool>.value(true)),
  // 壳层里的偏好同步会经 ApiClient 取 baseUrl；测试给一个合法环境，
  // 让链路走到 HTTP 层（被上面的封面替身接住），而不是 fail-fast。
  appEnvironmentProvider.overrideWithValue(
    const AppEnvironment(
      apiBaseUrl: 'https://example.test/',
      wsBaseUrl: 'wss://example.test/',
    ),
  ),
];

/// 桌面主题 + 视口 + 本地化的最小包装，不挂真实路由。
Widget wrapDesktop(
  Widget child, {
  Size viewport = kDesktopViewport,
  bool dark = true,
  DesktopAccent accent = DesktopAccent.sage,
}) {
  return MediaQuery(
    data: MediaQueryData(size: viewport, devicePixelRatio: 1),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: DesktopTheme.resolve(isDark: dark, accent: accent),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: ColoredBox(
        color:
            DesktopTheme.resolve(
              isDark: dark,
              accent: accent,
            ).scaffoldBackgroundColor,
        child: Scaffold(body: child),
      ),
    ),
  );
}

/// 让所有网络封面都拿到同一张真实 JPEG： golden 里能看到实际构图，
/// 而不是测试默认 HTTP 客户端返回的透明像素。
class DesktopImageOverrides extends HttpOverrides {
  DesktopImageOverrides(this.bytes);

  final Uint8List bytes;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(bytes);
}

class _FakeHttpClient extends Fake implements HttpClient {
  _FakeHttpClient(this.bytes);

  final Uint8List bytes;

  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeRequest(bytes);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeRequest(bytes);

  @override
  void close({bool force = false}) {}
}

class _FakeRequest extends Fake implements HttpClientRequest {
  _FakeRequest(this.bytes);

  final Uint8List bytes;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(bytes);

  @override
  void add(List<int> data) {}

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
}

class _FakeHeaders extends Fake implements HttpHeaders {
  final Map<String, List<String>> _values = {};

  @override
  List<String>? operator [](String name) => _values[name];

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name, () => []).add('$value');
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name] = ['$value'];
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  void removeAll(String name) => _values.remove(name);

  @override
  bool persistentConnection = true;

  @override
  int contentLength = -1;

  @override
  bool chunkedTransferEncoding = false;
}

class _FakeResponse extends Fake implements HttpClientResponse {
  _FakeResponse(this.bytes);

  final Uint8List bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpHeaders get headers => _FakeHeaders();

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<Uint8List>.fromIterable([bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
