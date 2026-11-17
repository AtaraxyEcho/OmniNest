/// 音乐模块提供给组合根（Portal 首页、桌面统一壳）的稳定集成契约。
library;

export 'package:omninest/features/music/application/music_portal_integration.dart'
    show
        MusicPortalActions,
        MusicPortalAlbum,
        MusicPortalLyricLine,
        MusicPortalPlaybackTimeline,
        MusicPortalSnapshot,
        MusicPortalTrack,
        musicPortalActionsProvider,
        musicPortalPlaybackTimelineProvider,
        musicPortalSnapshotProvider;
// 控制器库整份导出：歌单开放/续页/入播都是扩展方法，`show` 白名单
// 导不出无名扩展，桌面页只会看到 build。
export 'package:omninest/features/music/application/music_controller.dart';
export 'package:omninest/features/music/application/music_cover_artwork.dart'
    show musicCoverCacheManagerProvider, musicCoverRenderMethodForWeb;
export 'package:omninest/features/music/application/music_immersive_controller.dart'
    show musicImmersiveControllerProvider;
// 桌面常驻播放条需要「播放模式 / 收藏 / 队列编辑 / 音量」四类命令。
// 它们原先只被模块自己的页面消费，壳层成为第二个消费方后按门面收口，
// 而不是让 app 层直接 import 模块 application 内部文件。
export 'package:omninest/features/music/application/music_playback_session.dart'
    show musicAudioPlaybackProvider;
export 'package:omninest/features/music/domain/music_models.dart'
    show MusicAlbum, MusicPlaylist, MusicTrack;
export 'package:omninest/features/music/domain/music_playable_item.dart'
    show MusicPlayableItem;
export 'package:omninest/features/music/domain/music_visualizer_preset.dart'
    show
        PortalGlassPlayerSettings,
        PortalLyricVisualSettings,
        PortalMusicLayout,
        PortalMusicVisualizerPreferences,
        PortalMusicVisualizerSettings;
