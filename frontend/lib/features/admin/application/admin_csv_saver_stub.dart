import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// 通过系统保存对话框保存 CSV 字节，返回保存路径；取消时返回 null。
Future<String?> saveAdminCsvBytes({
  required String suggestedName,
  required Uint8List bytes,
}) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const <XTypeGroup>[
      XTypeGroup(label: 'CSV', extensions: <String>['csv']),
    ],
  );
  if (location == null) {
    return null;
  }
  final file = File(location.path);
  await file.writeAsBytes(bytes, flush: true);
  return location.path;
}
