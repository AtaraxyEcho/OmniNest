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
export 'package:omninest/features/music/domain/music_visualizer_preset.dart'
    show
        PortalGlassPlayerSettings,
        PortalLyricVisualSettings,
        PortalMusicLayout,
        PortalMusicVisualizerPreferences,
        PortalMusicVisualizerSettings;
