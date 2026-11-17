enum PreferenceSyncState { synced, pending }

class PreferenceSnapshot {
  const PreferenceSnapshot({
    required this.scope,
    required this.preferences,
    this.createdAt,
    this.updatedAt,
    this.version,
    this.syncState = PreferenceSyncState.synced,
  });

  factory PreferenceSnapshot.empty(String scope) {
    return PreferenceSnapshot(scope: scope, preferences: const {});
  }

  factory PreferenceSnapshot.fromJson(Map<String, dynamic> json) {
    final rawPreferences = json['preferences'];
    return PreferenceSnapshot(
      scope: json['scope']?.toString() ?? '',
      preferences:
          rawPreferences is Map
              ? Map<String, dynamic>.from(rawPreferences)
              : const {},
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      version: (json['version'] as num?)?.toInt(),
      syncState:
          json['syncState'] == PreferenceSyncState.pending.name
              ? PreferenceSyncState.pending
              : PreferenceSyncState.synced,
    );
  }

  final String scope;
  final Map<String, dynamic> preferences;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? version;
  final PreferenceSyncState syncState;

  PreferenceSnapshot copyWith({
    Map<String, dynamic>? preferences,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? version,
    PreferenceSyncState? syncState,
  }) {
    return PreferenceSnapshot(
      scope: scope,
      preferences: preferences ?? this.preferences,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      syncState: syncState ?? this.syncState,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scope': scope,
      'preferences': preferences,
      'createdAt': createdAt?.toUtc().toIso8601String(),
      'updatedAt': updatedAt?.toUtc().toIso8601String(),
      'version': version,
      'syncState': syncState.name,
    };
  }
}

class PreferenceMutation {
  const PreferenceMutation({required this.changes, required this.removeKeys});

  factory PreferenceMutation.fromJson(Map<String, dynamic> json) {
    final rawChanges = json['changes'];
    final rawRemoveKeys = json['removeKeys'];
    return PreferenceMutation(
      changes:
          rawChanges is Map ? Map<String, dynamic>.from(rawChanges) : const {},
      removeKeys:
          rawRemoveKeys is List
              ? rawRemoveKeys.map((value) => value.toString()).toSet()
              : const {},
    );
  }

  final Map<String, dynamic> changes;
  final Set<String> removeKeys;

  bool get isEmpty => changes.isEmpty && removeKeys.isEmpty;

  PreferenceMutation merge({
    required Map<String, dynamic> nextChanges,
    required Set<String> nextRemoveKeys,
  }) {
    final mergedChanges = Map<String, dynamic>.from(changes)
      ..addAll(nextChanges);
    final mergedRemoveKeys = <String>{...removeKeys, ...nextRemoveKeys};
    for (final key in nextChanges.keys) {
      mergedRemoveKeys.remove(key);
    }
    for (final key in nextRemoveKeys) {
      mergedChanges.remove(key);
    }
    return PreferenceMutation(
      changes: mergedChanges,
      removeKeys: mergedRemoveKeys,
    );
  }

  Map<String, dynamic> toJson() {
    return {'changes': changes, 'removeKeys': removeKeys.toList()..sort()};
  }
}
