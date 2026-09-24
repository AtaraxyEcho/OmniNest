/// 音乐模块提供给 Portal 的稳定集成契约。
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
export 'package:omninest/features/music/application/music_controller.dart'
    show MusicCenterState, musicCenterControllerProvider;
export 'package:omninest/features/music/application/music_cover_artwork.dart'
    show musicCoverCacheManagerProvider, musicCoverRenderMethodForWeb;
export 'package:omninest/features/music/application/music_immersive_controller.dart'
    show musicImmersiveControllerProvider;
export 'package:omninest/features/music/domain/music_playable_item.dart'
    show MusicPlayableItem;
export 'package:omninest/features/music/domain/music_visualizer_preset.dart'
    show
        PortalGlassPlayerSettings,
        PortalLyricVisualSettings,
        PortalMusicLayout,
        PortalMusicVisualizerPreferences,
        PortalMusicVisualizerSettings;
