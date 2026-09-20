import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/web_music_audio_playback.dart';

/// Web 端创建 HTMLAudioElement 播放器（SoLoud 为 FFI 原生库，Web 无实现）。
MusicAudioPlayback createMusicAudioPlayer() => WebMusicAudioPlayback();
