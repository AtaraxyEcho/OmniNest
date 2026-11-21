part of 'music_api.dart';

MusicPagedResult<T> _parseMusicPage<T>(
  Map<String, dynamic>? body,
  T Function(Map<String, dynamic>) mapper,
  String errorMessage,
) {
  final data = _parseMusicEnvelope(body)['data'];
  if (data is! Map) {
    throw AppException(code: 'INVALID_RESPONSE', message: errorMessage);
  }
  final rawItems = data['items'];
  if (rawItems is! List) {
    throw AppException(code: 'INVALID_RESPONSE', message: errorMessage);
  }
  return MusicPagedResult<T>(
    items:
        rawItems
            .whereType<Map>()
            .map((item) => mapper(Map<String, dynamic>.from(item)))
            .toList(),
    page: _asIntOrNull(data['page']),
    size: _asIntOrNull(data['size']),
    totalElements: _asIntOrNull(data['totalElements']),
  );
}

int _asIntOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

List<T> _parseMusicList<T>(
  Map<String, dynamic>? body,
  T Function(Map<String, dynamic>) mapper,
  String errorMessage,
) {
  final data = _parseMusicEnvelope(body)['data'];
  if (data is! List) {
    throw AppException(code: 'INVALID_RESPONSE', message: errorMessage);
  }
  return data
      .whereType<Map>()
      .map((item) => mapper(Map<String, dynamic>.from(item)))
      .toList();
}

/// 校验音乐接口信封并原样返回；`null` 视为服务端未返回结果。
Map<String, dynamic> _parseMusicEnvelope(Map<String, dynamic>? body) {
  if (body == null) {
    throw const AppException(code: 'EMPTY_RESPONSE', message: '服务端没有返回音乐结果');
  }
  final code = body['code'];
  if (code != 200) {
    final errorName = body['errorName']?.toString();
    throw AppException(
      code: errorName ?? code?.toString() ?? 'MUSIC_ERROR',
      message: body['message']?.toString() ?? '音乐操作失败',
      details: {
        if (errorName != null) 'errorName': errorName,
        if (code != null) 'code': code.toString(),
      },
    );
  }
  return body;
}
