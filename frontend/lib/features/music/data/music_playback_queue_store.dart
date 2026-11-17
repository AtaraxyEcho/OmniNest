import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class MusicPlaybackQueueStore {
  Future<MusicPlaybackQueueSnapshot?> load(String ownerId);

  Future<void> save(String ownerId, MusicPlaybackQueueSnapshot snapshot);
}

class SharedPreferencesMusicPlaybackQueueStore
    implements MusicPlaybackQueueStore {
  const SharedPreferencesMusicPlaybackQueueStore();

  static const String _keyPrefix = 'music_playback_queue_v1_';

  @override
  Future<MusicPlaybackQueueSnapshot?> load(String ownerId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(ownerId));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return MusicPlaybackQueueSnapshot.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(String ownerId, MusicPlaybackQueueSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(ownerId), jsonEncode(snapshot.toCacheJson()));
  }

  String _key(String ownerId) {
    return '$_keyPrefix${Uri.encodeComponent(ownerId)}';
  }
}

final musicPlaybackQueueStoreProvider = Provider<MusicPlaybackQueueStore>((
  ref,
) {
  return const SharedPreferencesMusicPlaybackQueueStore();
});
