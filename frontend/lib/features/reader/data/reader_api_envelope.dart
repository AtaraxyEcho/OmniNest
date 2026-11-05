part of 'reader_api.dart';

/// 阅读器响应信封解析。
///
/// 从 [ReaderApi] 拆出：所有接口的返回值都要过同一道信封校验，校验规则与具体
/// 资源无关。放在同一个库里用 mixin 注入，调用点（`parseData`/`parseList`）
/// 保持原样，既不改外部签名，也不让主类继续膨胀。
mixin _ReaderEnvelopeParsing {
  /// 从响应信封中提取 data 对象
  Map<String, dynamic> parseData(Map<String, dynamic>? body) {
    final envelope = parseEnvelope(body);
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const AppException(code: 'INVALID_RESPONSE', message: '阅读器响应格式不正确');
    }
    return data;
  }

  /// 从响应信封中提取 data 数组
  List<Map<String, dynamic>> parseList(Map<String, dynamic>? body) {
    final envelope = parseEnvelope(body);
    final data = envelope['data'];
    if (data is! List) {
      throw const AppException(
        code: 'INVALID_RESPONSE',
        message: '阅读器列表响应格式不正确',
      );
    }
    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  /// 解析响应信封，校验 code 字段
  ///
  /// `errorName` 是后端 `ErrorCode` 枚举名（稳定符号），放进 details 供调用方分辨
  /// "资源已不存在"这类可以幂等吞掉的业务错误；`code` 保持数字串不变，避免改动既有
  /// 按 code 分支的调用点。
  Map<String, dynamic> parseEnvelope(Map<String, dynamic>? body) {
    if (body == null) {
      throw const AppException(code: 'EMPTY_RESPONSE', message: '服务端没有返回阅读器结果');
    }
    final code = body['code'];
    if (code != 200) {
      final errorName = body['errorName']?.toString();
      throw AppException(
        code: errorName ?? code?.toString() ?? 'READER_ERROR',
        message: body['message']?.toString() ?? '阅读器操作失败',
        details: {
          if (errorName != null) 'errorName': errorName,
          if (code != null) 'code': code.toString(),
        },
      );
    }
    return body;
  }

  /// 将信封 data 数组映射为强类型列表
  List<T> _parseList<T>(
    Map<String, dynamic>? body,
    T Function(Map<String, dynamic>) mapper,
    String errorMessage,
  ) {
    final data = parseEnvelope(body)['data'];
    if (data is! List) {
      throw AppException(code: 'INVALID_RESPONSE', message: errorMessage);
    }
    return data
        .whereType<Map>()
        .map((item) => mapper(Map<String, dynamic>.from(item)))
        .toList();
  }
}
