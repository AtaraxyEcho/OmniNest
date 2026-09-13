class PortalSpectrumVisualSettings {
  const PortalSpectrumVisualSettings({
    required this.lowResponse,
    required this.midResponse,
    required this.highResponse,
  });

  factory PortalSpectrumVisualSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return defaults;
    }
    return PortalSpectrumVisualSettings(
      lowResponse: _readDouble(
        json['lowResponse'] ?? json['lowExpansion'],
        defaults.lowResponse,
      ),
      midResponse: _readDouble(
        json['midResponse'] ?? json['midLift'],
        defaults.midResponse,
      ),
      highResponse: _readDouble(
        json['highResponse'] ?? json['highSpark'],
        defaults.highResponse,
      ),
    );
  }

  static const defaults = PortalSpectrumVisualSettings(
    lowResponse: 1.08,
    midResponse: 0.96,
    highResponse: 0.82,
  );

  final double lowResponse;
  final double midResponse;
  final double highResponse;

  PortalSpectrumVisualSettings copyWith({
    double? lowResponse,
    double? midResponse,
    double? highResponse,
  }) {
    return PortalSpectrumVisualSettings(
      lowResponse: lowResponse ?? this.lowResponse,
      midResponse: midResponse ?? this.midResponse,
      highResponse: highResponse ?? this.highResponse,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'lowResponse': lowResponse,
      'midResponse': midResponse,
      'highResponse': highResponse,
    };
  }
}

class PortalCoverElementSettings {
  const PortalCoverElementSettings({
    required this.originalCoverEnabled,
    required this.borderEnabled,
    required this.sizeScale,
    required this.cornerRadius,
    required this.opacity,
    required this.tiltDegrees,
  });

  factory PortalCoverElementSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return defaults;
    }
    return PortalCoverElementSettings(
      originalCoverEnabled:
          json['originalCoverEnabled'] as bool? ??
          defaults.originalCoverEnabled,
      borderEnabled: json['borderEnabled'] as bool? ?? defaults.borderEnabled,
      sizeScale: _readDouble(json['sizeScale'], defaults.sizeScale),
      cornerRadius: _readDouble(json['cornerRadius'], defaults.cornerRadius),
      opacity: _readDouble(json['opacity'], defaults.opacity),
      tiltDegrees:
          _readDouble(
            json['tiltDegrees'],
            defaults.tiltDegrees,
          ).clamp(-12.0, 12.0).toDouble(),
    );
  }

  static const defaults = PortalCoverElementSettings(
    originalCoverEnabled: false,
    borderEnabled: false,
    sizeScale: 1,
    cornerRadius: 8,
    opacity: 1,
    tiltDegrees: 0,
  );

  final bool originalCoverEnabled;
  final bool borderEnabled;
  final double sizeScale;
  final double cornerRadius;
  final double opacity;
  final double tiltDegrees;

  PortalCoverElementSettings copyWith({
    bool? originalCoverEnabled,
    bool? borderEnabled,
    double? sizeScale,
    double? cornerRadius,
    double? opacity,
    double? tiltDegrees,
  }) {
    return PortalCoverElementSettings(
      originalCoverEnabled: originalCoverEnabled ?? this.originalCoverEnabled,
      borderEnabled: borderEnabled ?? this.borderEnabled,
      sizeScale: sizeScale ?? this.sizeScale,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      opacity: opacity ?? this.opacity,
      tiltDegrees: tiltDegrees ?? this.tiltDegrees,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'originalCoverEnabled': originalCoverEnabled,
      'borderEnabled': borderEnabled,
      'sizeScale': sizeScale,
      'cornerRadius': cornerRadius,
      'opacity': opacity,
      'tiltDegrees': tiltDegrees,
    };
  }
}

enum PortalLyricPosition { left, center, right }

class PortalLyricVisualSettings {
  const PortalLyricVisualSettings({
    required this.enabled,
    required this.currentFontScale,
    required this.inactiveOpacity,
    required this.visibleLines,
    required this.lineSpacing,
    required this.activeColorValue,
    required this.readColorValue,
    required this.unreadColorValue,
    required this.breathingEnabled,
    required this.shadowEnabled,
    required this.glowIntensity,
    required this.glowColorValue,
    required this.position,
  });

  factory PortalLyricVisualSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return defaults;
    }
    return PortalLyricVisualSettings(
      enabled: json['enabled'] as bool? ?? true,
      currentFontScale: _readDouble(
        json['currentFontScale'],
        defaults.currentFontScale,
      ),
      inactiveOpacity: _readDouble(
        json['inactiveOpacity'],
        defaults.inactiveOpacity,
      ),
      visibleLines: _normalizeLyricVisibleLines(json['visibleLines']),
      lineSpacing:
          _readDouble(
            json['lineSpacing'],
            defaults.lineSpacing,
          ).clamp(0.75, 1.65).toDouble(),
      activeColorValue: _readColorValue(
        json['activeColorValue'] ?? json['textColorValue'],
        defaults.activeColorValue,
      ),
      readColorValue: _readColorValue(
        json['readColorValue'],
        defaults.readColorValue,
      ),
      unreadColorValue: _readColorValue(
        json['unreadColorValue'],
        defaults.unreadColorValue,
      ),
      breathingEnabled: json['breathingEnabled'] as bool? ?? true,
      shadowEnabled: json['shadowEnabled'] as bool? ?? true,
      glowIntensity:
          _readDouble(
            json['glowIntensity'],
            defaults.glowIntensity,
          ).clamp(0.0, 2.0).toDouble(),
      glowColorValue: _readColorValue(
        json['glowColorValue'],
        defaults.glowColorValue,
      ),
      position: _parseLyricPosition(json['position']),
    );
  }

  static const defaults = PortalLyricVisualSettings(
    enabled: true,
    currentFontScale: 1,
    inactiveOpacity: 0.46,
    visibleLines: 3,
    lineSpacing: 1,
    activeColorValue: 0xFF72D6C9,
    readColorValue: 0xFF8DA2A7,
    unreadColorValue: 0xFFFFFFFF,
    breathingEnabled: true,
    shadowEnabled: true,
    glowIntensity: 1,
    glowColorValue: 0xFF9FDBE3,
    position: PortalLyricPosition.center,
  );

  static const mineradioClassic = defaults;

  final bool enabled;
  final double currentFontScale;
  final double inactiveOpacity;
  final int visibleLines;
  final double lineSpacing;
  final int activeColorValue;
  final int readColorValue;
  final int unreadColorValue;
  final bool breathingEnabled;
  final bool shadowEnabled;
  final double glowIntensity;
  final int glowColorValue;
  final PortalLyricPosition position;

  bool get wordHighlightEnabled => false;

  bool get reflectionEnabled => false;

  PortalLyricVisualSettings copyWith({
    bool? enabled,
    double? currentFontScale,
    double? inactiveOpacity,
    int? visibleLines,
    double? lineSpacing,
    int? activeColorValue,
    int? readColorValue,
    int? unreadColorValue,
    bool? breathingEnabled,
    bool? shadowEnabled,
    double? glowIntensity,
    int? glowColorValue,
    PortalLyricPosition? position,
  }) {
    return PortalLyricVisualSettings(
      enabled: enabled ?? this.enabled,
      currentFontScale: currentFontScale ?? this.currentFontScale,
      inactiveOpacity: inactiveOpacity ?? this.inactiveOpacity,
      visibleLines: visibleLines ?? this.visibleLines,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      activeColorValue: activeColorValue ?? this.activeColorValue,
      readColorValue: readColorValue ?? this.readColorValue,
      unreadColorValue: unreadColorValue ?? this.unreadColorValue,
      breathingEnabled: breathingEnabled ?? this.breathingEnabled,
      shadowEnabled: shadowEnabled ?? this.shadowEnabled,
      glowIntensity: glowIntensity ?? this.glowIntensity,
      glowColorValue: glowColorValue ?? this.glowColorValue,
      position: position ?? this.position,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'currentFontScale': currentFontScale,
      'inactiveOpacity': inactiveOpacity,
      'visibleLines': visibleLines,
      'lineSpacing': lineSpacing,
      'activeColorValue': activeColorValue,
      'readColorValue': readColorValue,
      'unreadColorValue': unreadColorValue,
      'breathingEnabled': breathingEnabled,
      'shadowEnabled': shadowEnabled,
      'glowIntensity': glowIntensity,
      'glowColorValue': glowColorValue,
      'position': position.name,
    };
  }
}

enum MusicAudioBarStyle { spectrumBars, lineWave, pulseDots }

class PortalGlassPlayerSettings {
  const PortalGlassPlayerSettings({
    required this.enabled,
    required this.audioBarEnabled,
    required this.audioBarStyle,
    required this.volumeEnabled,
    required this.progressEnabled,
  });

  factory PortalGlassPlayerSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return defaults;
    }
    return PortalGlassPlayerSettings(
      enabled: json['enabled'] as bool? ?? true,
      audioBarEnabled: json['audioBarEnabled'] as bool? ?? true,
      audioBarStyle: _parseAudioBarStyle(json['audioBarStyle']),
      volumeEnabled: json['volumeEnabled'] as bool? ?? true,
      progressEnabled: json['progressEnabled'] as bool? ?? true,
    );
  }

  static const defaults = PortalGlassPlayerSettings(
    enabled: true,
    audioBarEnabled: true,
    audioBarStyle: MusicAudioBarStyle.spectrumBars,
    volumeEnabled: true,
    progressEnabled: true,
  );

  final bool enabled;
  final bool audioBarEnabled;
  final MusicAudioBarStyle audioBarStyle;
  final bool volumeEnabled;
  final bool progressEnabled;

  PortalGlassPlayerSettings copyWith({
    bool? enabled,
    bool? audioBarEnabled,
    MusicAudioBarStyle? audioBarStyle,
    bool? volumeEnabled,
    bool? progressEnabled,
  }) {
    return PortalGlassPlayerSettings(
      enabled: enabled ?? this.enabled,
      audioBarEnabled: audioBarEnabled ?? this.audioBarEnabled,
      audioBarStyle: audioBarStyle ?? this.audioBarStyle,
      volumeEnabled: volumeEnabled ?? this.volumeEnabled,
      progressEnabled: progressEnabled ?? this.progressEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'audioBarEnabled': audioBarEnabled,
      'audioBarStyle': audioBarStyle.name,
      'volumeEnabled': volumeEnabled,
      'progressEnabled': progressEnabled,
    };
  }
}

class PortalMusicVisualizerSettings {
  const PortalMusicVisualizerSettings({
    required this.spectrum,
    required this.coverElements,
    required this.lyrics,
    required this.player,
  });

  factory PortalMusicVisualizerSettings.fromJson(Map<String, dynamic>? json) {
    return PortalMusicVisualizerSettings(
      spectrum: PortalSpectrumVisualSettings.fromJson(
        _readMap(json?['spectrum']) ?? _readMap(json?['coverParticles']),
      ),
      coverElements: PortalCoverElementSettings.fromJson(
        _readMap(json?['coverElements']),
      ),
      lyrics: PortalLyricVisualSettings.fromJson(_readMap(json?['lyrics'])),
      player: PortalGlassPlayerSettings.fromJson(_readMap(json?['player'])),
    );
  }

  static const defaults = PortalMusicVisualizerSettings(
    spectrum: PortalSpectrumVisualSettings.defaults,
    coverElements: PortalCoverElementSettings.defaults,
    lyrics: PortalLyricVisualSettings.defaults,
    player: PortalGlassPlayerSettings.defaults,
  );

  final PortalSpectrumVisualSettings spectrum;
  final PortalCoverElementSettings coverElements;
  final PortalLyricVisualSettings lyrics;
  final PortalGlassPlayerSettings player;

  PortalMusicVisualizerSettings copyWith({
    PortalSpectrumVisualSettings? spectrum,
    PortalCoverElementSettings? coverElements,
    PortalLyricVisualSettings? lyrics,
    PortalGlassPlayerSettings? player,
  }) {
    return PortalMusicVisualizerSettings(
      spectrum: spectrum ?? this.spectrum,
      coverElements: coverElements ?? this.coverElements,
      lyrics: lyrics ?? this.lyrics,
      player: player ?? this.player,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'spectrum': spectrum.toJson(),
      'coverElements': coverElements.toJson(),
      'lyrics': lyrics.toJson(),
      'player': player.toJson(),
    };
  }
}

class PortalMusicVisualizerPreferences {
  const PortalMusicVisualizerPreferences({
    this.schemaVersion = currentSchemaVersion,
    this.visual = PortalMusicVisualizerSettings.defaults,
  });

  static const int currentSchemaVersion = 5;

  factory PortalMusicVisualizerPreferences.fromJson(Map<String, dynamic> json) {
    final visual = _readMap(json['visual']) ?? _readLegacyVisual(json);
    return PortalMusicVisualizerPreferences(
      schemaVersion: currentSchemaVersion,
      visual: PortalMusicVisualizerSettings.fromJson(visual),
    );
  }

  final int schemaVersion;
  final PortalMusicVisualizerSettings visual;

  PortalMusicVisualizerPreferences copyWith({
    int? schemaVersion,
    PortalMusicVisualizerSettings? visual,
  }) {
    return PortalMusicVisualizerPreferences(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      visual: visual ?? this.visual,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': currentSchemaVersion,
      'visual': visual.toJson(),
    };
  }
}

Map<String, dynamic>? _readLegacyVisual(Map<String, dynamic> json) {
  final selectedId = json['selectedPresetId']?.toString();
  final customPresets = json['customPresets'];
  if (selectedId == null || customPresets is! List) {
    return null;
  }
  for (final item in customPresets) {
    if (item is Map<String, dynamic> && item['id']?.toString() == selectedId) {
      return item;
    }
  }
  return null;
}

double _readDouble(Object? value, double fallback) {
  return value is num ? value.toDouble() : fallback;
}

int _normalizeLyricVisibleLines(Object? value) {
  final lines = (value as num?)?.toInt() ?? 3;
  return lines.clamp(1, 9).toInt();
}

int _readColorValue(Object? value, int fallback) {
  return value is num ? value.toInt() : fallback;
}

PortalLyricPosition _parseLyricPosition(Object? value) {
  return PortalLyricPosition.values.firstWhere(
    (position) => position.name == value?.toString(),
    orElse: () => PortalLyricPosition.center,
  );
}

MusicAudioBarStyle _parseAudioBarStyle(Object? value) {
  if (value?.toString() == 'mirroredWave') {
    return MusicAudioBarStyle.lineWave;
  }
  return MusicAudioBarStyle.values.firstWhere(
    (style) => style.name == value?.toString(),
    orElse: () => MusicAudioBarStyle.spectrumBars,
  );
}

Map<String, dynamic>? _readMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}
