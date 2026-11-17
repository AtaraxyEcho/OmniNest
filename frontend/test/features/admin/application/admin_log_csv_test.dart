import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/admin/application/admin_log_csv.dart';

void main() {
  group('adminCsvDocument', () {
    test('writes BOM, header and rows', () {
      final csv = adminCsvDocument(
        header: ['a', 'b'],
        rows: [
          ['1', '2'],
          ['3', '4'],
        ],
      );
      expect(csv.startsWith('\uFEFF'), isTrue);
      expect(csv, contains('\uFEFFa,b\n1,2\n3,4\n'));
    });

    test('quotes cells containing comma, quote or newline', () {
      final csv = adminCsvDocument(
        header: ['h'],
        rows: [
          ['plain'],
          ['with,comma'],
          ['with"quote'],
          ['multi\nline'],
          ['crlf\r\nline'],
        ],
      );
      expect(csv, contains('\nplain\n'));
      expect(csv, contains('\n"with,comma"\n'));
      expect(csv, contains('\n"with""quote"\n'));
      expect(csv, contains('\n"multi\nline"\n'));
      expect(csv, contains('\n"crlf\nline"\n'));
    });

    test('output round-trips as utf-8 with BOM bytes', () {
      final csv = adminCsvDocument(
        header: ['操作类型'],
        rows: [
          ['USER_CREATE'],
        ],
      );
      final bytes = utf8.encode(csv);
      expect(bytes.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
      final decoded = utf8.decode(bytes);
      expect(decoded, contains('操作类型'));
      expect(decoded, contains('USER_CREATE'));
    });
  });
}
