class MovieFiles {
  const MovieFiles({required this.files, required this.transcodingEnabled});

  final List<MovieVideoFile> files;
  final bool transcodingEnabled;

  factory MovieFiles.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    return MovieFiles(
      files:
          rawFiles is List
              ? rawFiles
                  .whereType<Map<String, dynamic>>()
                  .map(MovieVideoFile.fromJson)
                  .toList(growable: false)
              : const [],
      transcodingEnabled: json['transcodingEnabled'] == true,
    );
  }
}

class MovieVideoFile {
  const MovieVideoFile({
    required this.videoItemId,
    required this.fileNodeId,
    required this.fileName,
    required this.sizeBytes,
    required this.primary,
    this.mimeType,
    this.versionLabel,
    this.videoCodec,
    this.audioCodec,
    this.containerFormat,
    this.resolutionWidth,
    this.resolutionHeight,
  });

  final String videoItemId;
  final String fileNodeId;
  final String fileName;
  final int sizeBytes;
  final String? mimeType;
  final String? versionLabel;
  final bool primary;
  final String? videoCodec;
  final String? audioCodec;
  final String? containerFormat;
  final int? resolutionWidth;
  final int? resolutionHeight;

  factory MovieVideoFile.fromJson(Map<String, dynamic> json) {
    return MovieVideoFile(
      videoItemId: json['videoItemId']?.toString() ?? '',
      fileNodeId: json['fileNodeId']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      sizeBytes: _asInt(json['sizeBytes']),
      mimeType: json['mimeType']?.toString(),
      versionLabel: json['versionLabel']?.toString(),
      primary: json['primary'] == true,
      videoCodec: json['videoCodec']?.toString(),
      audioCodec: json['audioCodec']?.toString(),
      containerFormat: json['containerFormat']?.toString(),
      resolutionWidth:
          json['resolutionWidth'] == null
              ? null
              : _asInt(json['resolutionWidth']),
      resolutionHeight:
          json['resolutionHeight'] == null
              ? null
              : _asInt(json['resolutionHeight']),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
