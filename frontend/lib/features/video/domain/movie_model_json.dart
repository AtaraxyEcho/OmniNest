/// 影视领域模型的宽松 JSON 值解码器。
final class MovieJson {
  const MovieJson._();

  static List<Map<String, dynamic>> asList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value.whereType<Map<String, dynamic>>().toList();
  }

  static Map<String, dynamic> asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  static int asInt(Object? value) {
    return switch (value) {
      final int number => number,
      final num number => number.toInt(),
      final String text => int.tryParse(text) ?? 0,
      _ => 0,
    };
  }

  static double asDouble(Object? value) {
    return switch (value) {
      final double number => number,
      final num number => number.toDouble(),
      final String text => double.tryParse(text) ?? 0,
      _ => 0,
    };
  }

  static List<String> stringList(Object? value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return const [];
  }

  static int? nullableInt(Object? value) {
    if (value == null) return null;
    return asInt(value);
  }

  static double? nullableDouble(Object? value) {
    if (value == null) return null;
    return asDouble(value);
  }
}
