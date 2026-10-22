/// 关系图谱数据模型：节点（相册/时间/地点）与共现边。
///
/// 数据来自 `/photos/relations` 聚合端点，自洽且与分页列表无关。
library;

/// 关系节点类型，取值与后端一致。
enum PhotoRelationNodeType {
  album('ALBUM'),
  time('TIME'),
  location('LOCATION');

  const PhotoRelationNodeType(this.value);

  final String value;

  static PhotoRelationNodeType? tryFrom(String? value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// 关系图谱节点。
class PhotoRelationNode {
  const PhotoRelationNode({
    required this.type,
    required this.key,
    required this.label,
    required this.weight,
  });

  factory PhotoRelationNode.fromJson(Map<String, dynamic> json) {
    return PhotoRelationNode(
      type:
          PhotoRelationNodeType.tryFrom(json['type']?.toString()) ??
          PhotoRelationNodeType.album,
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString(),
      weight: int.tryParse(json['weight']?.toString() ?? '') ?? 0,
    );
  }

  final PhotoRelationNodeType type;
  final String key;

  /// 展示名；时间/地点节点为空时由调用方使用 key 展示。
  final String? label;
  final int weight;
}

/// 关系图谱边：一对实体之间的共现照片数。
class PhotoRelationEdge {
  const PhotoRelationEdge({
    required this.sourceType,
    required this.sourceKey,
    required this.targetType,
    required this.targetKey,
    required this.weight,
  });

  factory PhotoRelationEdge.fromJson(Map<String, dynamic> json) {
    return PhotoRelationEdge(
      sourceType:
          PhotoRelationNodeType.tryFrom(json['sourceType']?.toString()) ??
          PhotoRelationNodeType.album,
      sourceKey: json['sourceKey']?.toString() ?? '',
      targetType:
          PhotoRelationNodeType.tryFrom(json['targetType']?.toString()) ??
          PhotoRelationNodeType.album,
      targetKey: json['targetKey']?.toString() ?? '',
      weight: int.tryParse(json['weight']?.toString() ?? '') ?? 0,
    );
  }

  final PhotoRelationNodeType sourceType;
  final String sourceKey;
  final PhotoRelationNodeType targetType;
  final String targetKey;
  final int weight;
}

/// 关系图谱完整数据。
class PhotoRelationGraph {
  const PhotoRelationGraph({
    required this.nodes,
    required this.edges,
    required this.truncated,
  });

  factory PhotoRelationGraph.fromJson(Map<String, dynamic> json) {
    return PhotoRelationGraph(
      nodes: (json['nodes'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => PhotoRelationNode.fromJson(Map.from(item)))
          .toList(growable: false),
      edges: (json['edges'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => PhotoRelationEdge.fromJson(Map.from(item)))
          .toList(growable: false),
      truncated: json['truncated'] == true,
    );
  }

  static const PhotoRelationGraph empty = PhotoRelationGraph(
    nodes: [],
    edges: [],
    truncated: false,
  );

  final List<PhotoRelationNode> nodes;
  final List<PhotoRelationEdge> edges;
  final bool truncated;
}
