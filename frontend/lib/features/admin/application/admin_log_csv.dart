import 'dart:convert';
import 'dart:typed_data';

import 'package:omninest/features/admin/application/admin_csv_saver.dart';

/// 将表格行转为 RFC 4180 兼容的 CSV 文本，并写入 BOM 以便 Excel 识别 UTF-8。
String adminCsvDocument({
  required List<String> header,
  required List<List<String>> rows,
}) {
  final buffer = StringBuffer('\uFEFF');
  buffer.writeln(_csvRow(header));
  for (final row in rows) {
    buffer.writeln(_csvRow(row));
  }
  return buffer.toString();
}

String _csvRow(List<String> cells) {
  return cells.map(_csvCell).join(',');
}

String _csvCell(String value) {
  var normalized = value.replaceAll('\r\n', '\n');
  // 公式注入中和：= + - @ 等开头的单元格前置单引号，
  // 避免 Excel/WPS 把用户可控内容（文件名、用户名等）当作公式或 DDE 执行
  if (normalized.isNotEmpty &&
      const ['=', '+', '-', '@', '\t'].contains(normalized[0])) {
    normalized = "'$normalized";
  }
  final needsQuote =
      normalized.contains(',') ||
      normalized.contains('"') ||
      normalized.contains('\n');
  final escaped = normalized.replaceAll('"', '""');
  return needsQuote ? '"$escaped"' : escaped;
}

/// 保存 CSV 文本：桌面端弹出系统保存对话框，Web 端触发浏览器下载。
///
/// 返回保存路径（Web 端为文件名）；用户取消选择时返回 null。
Future<String?> saveAdminCsvToDisk({
  required String suggestedName,
  required String csv,
}) {
  return saveAdminCsvBytes(
    suggestedName: suggestedName,
    bytes: Uint8List.fromList(utf8.encode(csv)),
  );
}
