part of 'music_controller.dart';

enum MusicSection {
  songs,
  albums,
  artists,
  customPlaylists,
  playlistDetail,
  albumDetail,
  artistDetail,
}

/// 播放模式：三态互斥，播放详情页与移动端播放页共用单按钮轮换。
///
/// [sequential] 是默认档，按队列顺序播放且首尾循环；[repeatOne] 只重复当前曲目。
enum MusicPlayMode { sequential, shuffle, repeatOne }

/// 播放域视图：刷新链路整体携带播放状态，避免逐字段穿参遗漏导致队列被静默重置。
class MusicPlaybackView {
  const MusicPlaybackView({
    this.currentItem,
    this.playbackPlan,
    this.isPlaying = false,
    this.playbackItems = const [],
    this.playbackIndex = -1,
    this.playMode = MusicPlayMode.sequential,
    this.queueSource = MusicQueueSource.transient,
  });

  final MusicPlayableItem? currentItem;
  final MusicPlaybackPlan? playbackPlan;
  final bool isPlaying;
  final List<MusicPlayableItem> playbackItems;
  final int playbackIndex;
  final MusicPlayMode playMode;
  final MusicQueueSource queueSource;
}

/// 汇总音乐曲库、播放队列和外部平台账号状态。
class MusicCenterState {
  const MusicCenterState({
    required this.dashboard,
    required this.tracks,
    required this.albums,
    required this.artists,
    required this.playlists,
    this.recentItems = const [],
    this.section = MusicSection.songs,
    this.currentItem,
    this.playbackPlan,
    this.isPlaying = false,
    this.playbackItems = const [],
    this.playbackIndex = -1,
    this.playMode = MusicPlayMode.sequential,
    this.queueSource = MusicQueueSource.transient,
    this.selectedPlaylist,
    this.selectedPlaylistTracks = const [],
    this.selectedAlbum,
    this.selectedAlbumTracks = const [],
    this.selectedArtist,
    this.selectedArtistTracks = const [],
    this.hasMoreTracks = false,
    this.tracksLoadingMore = false,
    this.lastScanJob,
    this.errorMessage,
    this.neteaseUserInfo,
  });

  final MusicDashboard dashboard;
  final List<MusicTrack> tracks;
  final List<MusicAlbum> albums;
  final List<MusicArtist> artists;
  final List<MusicPlaylist> playlists;
  final List<MusicPlayableItem> recentItems;
  final MusicSection section;
  final MusicPlayableItem? currentItem;
  final MusicPlaybackPlan? playbackPlan;
  final bool isPlaying;
  final List<MusicPlayableItem> playbackItems;
  final int playbackIndex;
  final MusicPlayMode playMode;
  final MusicQueueSource queueSource;
  final MusicPlaylist? selectedPlaylist;
  final List<MusicTrack> selectedPlaylistTracks;
  final MusicAlbum? selectedAlbum;
  final List<MusicTrack> selectedAlbumTracks;
  final MusicArtist? selectedArtist;
  final List<MusicTrack> selectedArtistTracks;
  final bool hasMoreTracks;
  final bool tracksLoadingMore;
  final MusicScanJob? lastScanJob;
  final String? errorMessage;
  final PlatformUserInfo? neteaseUserInfo;

  bool get hasPlatformLoggedIn => neteaseUserInfo != null;

  /// 播放域视图，供刷新链路整体携带播放状态。
  MusicPlaybackView get playbackView => MusicPlaybackView(
    currentItem: currentItem,
    playbackPlan: playbackPlan,
    isPlaying: isPlaying,
    playbackItems: playbackItems,
    playbackIndex: playbackIndex,
    playMode: playMode,
    queueSource: queueSource,
  );

  MusicTrack? get currentTrack => currentItem?.track;

  List<MusicTrack> get playbackQueue =>
      playbackItems.map((item) => item.track).toList(growable: false);

  MusicTrack? get activeTrack => currentTrack;

  MusicPlayableItem? get activeItem => currentItem;

  MusicCenterState copyWith({
    MusicDashboard? dashboard,
    List<MusicTrack>? tracks,
    List<MusicAlbum>? albums,
    List<MusicArtist>? artists,
    List<MusicPlaylist>? playlists,
    List<MusicPlayableItem>? recentItems,
    MusicSection? section,
    MusicPlayableItem? currentItem,
    MusicPlaybackPlan? playbackPlan,
    bool? isPlaying,
    List<MusicPlayableItem>? playbackItems,
    int? playbackIndex,
    MusicPlayMode? playMode,
    MusicQueueSource? queueSource,
    MusicPlaylist? selectedPlaylist,
    List<MusicTrack>? selectedPlaylistTracks,
    MusicAlbum? selectedAlbum,
    List<MusicTrack>? selectedAlbumTracks,
    MusicArtist? selectedArtist,
    List<MusicTrack>? selectedArtistTracks,
    bool? hasMoreTracks,
    bool? tracksLoadingMore,
    bool clearCurrentTrack = false,
    bool clearPlaybackPlan = false,
    bool clearSelectedPlaylist = false,
    bool clearSelectedAlbum = false,
    bool clearSelectedArtist = false,
    MusicScanJob? lastScanJob,
    String? errorMessage,
    bool clearError = false,
    PlatformUserInfo? neteaseUserInfo,
    bool clearNeteaseUserInfo = false,
  }) {
    return MusicCenterState(
      dashboard: dashboard ?? this.dashboard,
      tracks: tracks ?? this.tracks,
      albums: albums ?? this.albums,
      artists: artists ?? this.artists,
      playlists: playlists ?? this.playlists,
      recentItems: recentItems ?? this.recentItems,
      section: section ?? this.section,
      currentItem: clearCurrentTrack ? null : currentItem ?? this.currentItem,
      playbackPlan:
          clearCurrentTrack || clearPlaybackPlan
              ? null
              : playbackPlan ?? this.playbackPlan,
      isPlaying: isPlaying ?? this.isPlaying,
      playbackItems: playbackItems ?? this.playbackItems,
      playbackIndex: playbackIndex ?? this.playbackIndex,
      playMode: playMode ?? this.playMode,
      queueSource: queueSource ?? this.queueSource,
      selectedPlaylist:
          clearSelectedPlaylist
              ? null
              : selectedPlaylist ?? this.selectedPlaylist,
      selectedPlaylistTracks:
          clearSelectedPlaylist
              ? const []
              : selectedPlaylistTracks ?? this.selectedPlaylistTracks,
      selectedAlbum:
          clearSelectedAlbum ? null : selectedAlbum ?? this.selectedAlbum,
      selectedAlbumTracks:
          clearSelectedAlbum
              ? const []
              : selectedAlbumTracks ?? this.selectedAlbumTracks,
      selectedArtist:
          clearSelectedArtist ? null : selectedArtist ?? this.selectedArtist,
      selectedArtistTracks:
          clearSelectedArtist
              ? const []
              : selectedArtistTracks ?? this.selectedArtistTracks,
      hasMoreTracks: hasMoreTracks ?? this.hasMoreTracks,
      tracksLoadingMore: tracksLoadingMore ?? this.tracksLoadingMore,
      lastScanJob: lastScanJob ?? this.lastScanJob,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      neteaseUserInfo:
          clearNeteaseUserInfo ? null : neteaseUserInfo ?? this.neteaseUserInfo,
    );
  }
}
