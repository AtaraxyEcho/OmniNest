/// 频谱帧来源。
enum MusicSpectrumSource { silent, estimated, nativeFft }

/// 音乐频谱帧。
class MusicSpectrumFrame {
  const MusicSpectrumFrame({
    required this.bands,
    required this.bass,
    required this.mid,
    required this.treble,
    required this.energy,
    required this.beat,
    required this.active,
    required this.source,
    required this.confidence,
    this.low = 0,
    this.body = 0,
    this.vocal = 0,
    this.snap = 0,
    this.lowDominance = 0,
    this.beatConfidence = 0,
    this.sequence = 0,
    this.capturedAtMicros = 0,
    this.audioPosition = Duration.zero,
  });

  final List<double> bands;
  final double bass;
  final double mid;
  final double treble;
  final double energy;
  final double beat;
  final bool active;
  final MusicSpectrumSource source;
  final double confidence;
  final double low;
  final double body;
  final double vocal;
  final double snap;
  final double lowDominance;
  final double beatConfidence;
  final int sequence;
  final int capturedAtMicros;
  final Duration audioPosition;

  bool get isEstimated => source == MusicSpectrumSource.estimated;

  MusicSpectrumFrame copyWith({
    List<double>? bands,
    double? bass,
    double? mid,
    double? treble,
    double? energy,
    double? beat,
    bool? active,
    MusicSpectrumSource? source,
    double? confidence,
    double? low,
    double? body,
    double? vocal,
    double? snap,
    double? lowDominance,
    double? beatConfidence,
    int? sequence,
    int? capturedAtMicros,
    Duration? audioPosition,
  }) {
    return MusicSpectrumFrame(
      bands: bands ?? this.bands,
      bass: bass ?? this.bass,
      mid: mid ?? this.mid,
      treble: treble ?? this.treble,
      energy: energy ?? this.energy,
      beat: beat ?? this.beat,
      active: active ?? this.active,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      low: low ?? this.low,
      body: body ?? this.body,
      vocal: vocal ?? this.vocal,
      snap: snap ?? this.snap,
      lowDominance: lowDominance ?? this.lowDominance,
      beatConfidence: beatConfidence ?? this.beatConfidence,
      sequence: sequence ?? this.sequence,
      capturedAtMicros: capturedAtMicros ?? this.capturedAtMicros,
      audioPosition: audioPosition ?? this.audioPosition,
    );
  }

  MusicSpectrumFrame decay(double amount) {
    final factor = (1 - amount.clamp(0.0, 1.0)).toDouble();
    return copyWith(
      bands: bands.map((value) => value * factor).toList(growable: false),
      bass: bass * factor,
      mid: mid * factor,
      treble: treble * factor,
      energy: energy * factor,
      beat: beat * factor * factor,
      confidence: confidence * factor,
      low: low * factor,
      body: body * factor,
      vocal: vocal * factor,
      snap: snap * factor,
      lowDominance: lowDominance * factor,
      beatConfidence: beatConfidence * factor,
      active: active && (energy * factor > 0.004 || confidence * factor > 0.02),
    );
  }

  static MusicSpectrumFrame silent({int bandCount = 32}) {
    return MusicSpectrumFrame(
      bands: List<double>.filled(bandCount, 0.08),
      bass: 0.06,
      mid: 0.04,
      treble: 0.03,
      energy: 0.05,
      beat: 0,
      active: false,
      source: MusicSpectrumSource.silent,
      confidence: 0,
      low: 0,
      body: 0,
      vocal: 0,
      snap: 0,
      lowDominance: 0,
      beatConfidence: 0,
      sequence: 0,
      capturedAtMicros: 0,
      audioPosition: Duration.zero,
    );
  }
}
