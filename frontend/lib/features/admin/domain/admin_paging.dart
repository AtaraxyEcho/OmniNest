typedef AdminTaskPageQuery =
    ({
      int page,
      int size,
      String status,
      String taskType,
      String query,
      String sort,
      String dir,
    });

typedef AdminLogPageQuery =
    ({
      int page,
      int size,
      String action,
      String query,
      String sort,
      String dir,
    });

typedef AdminSessionPageQuery =
    ({
      int page,
      int size,
      String status,
      String platform,
      String query,
      String sort,
      String dir,
    });

typedef AdminLoginAuditPageQuery =
    ({
      int page,
      int size,
      String result,
      String platform,
      String query,
      String sort,
      String dir,
    });

/// 批量操作逐项执行结果：成功条数与失败条目的 ID。
typedef AdminBatchResult = ({int successCount, List<String> failedIds});

/// 只有页码与条数的列表查询键（审计与只读维护列表共用）。
typedef AdminPagedQuery = ({int page, int size});

class AdminPage<T> {
  const AdminPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });

  factory AdminPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final rawItems = json['items'];
    final items =
        rawItems is List
            ? rawItems
                .whereType<Map>()
                .map((item) => itemFromJson(Map<String, dynamic>.from(item)))
                .toList(growable: false)
            : <T>[];
    return AdminPage(
      items: items,
      page: _int(json['page']),
      size: _int(json['size']),
      totalElements: _int(json['totalElements']),
      totalPages: _int(json['totalPages']),
    );
  }

  final List<T> items;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;

  bool get hasPrevious => page > 0;
  bool get hasNext => page + 1 < totalPages;
}

int _int(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
