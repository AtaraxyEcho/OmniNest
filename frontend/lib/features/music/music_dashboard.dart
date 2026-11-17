/// 音乐模块提供给跨 Feature 仪表盘的只读契约。
library;

export 'package:omninest/features/music/application/music_controller.dart'
    show musicDashboardProvider;
export 'package:omninest/features/music/domain/music_models.dart'
    show MusicAlbum, MusicDashboard, MusicTrack;
