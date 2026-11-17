import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/data/dtos/file_node_dto.dart';

void main() {
  group('SpaceType', () {
    test('fromValue_PERSONAL returns SpaceType.personal', () {
      expect(SpaceType.fromValue('PERSONAL'), SpaceType.personal);
    });

    test('fromValue_SHARED returns SpaceType.shared', () {
      expect(SpaceType.fromValue('SHARED'), SpaceType.shared);
    });

    test('fromValue_caseSensitive_matchesUppercase', () {
      expect(SpaceType.fromValue('PERSONAL'), SpaceType.personal);
      expect(SpaceType.fromValue('SHARED'), SpaceType.shared);
    });

    test('fromValue_unknownValue_returnsPersonal', () {
      expect(SpaceType.fromValue('UNKNOWN'), SpaceType.personal);
    });

    test('value property returns correct string', () {
      expect(SpaceType.personal.value, 'PERSONAL');
      expect(SpaceType.shared.value, 'SHARED');
    });
  });

  group('FileNode', () {
    test('default spaceType is personal', () {
      const node = FileNode(
        id: '1',
        parentId: null,
        name: 'test.txt',
        isFolder: false,
        nodeType: 'FILE',
        normalizedPath: '/test.txt',
        sizeBytes: 100,
        updatedAt: null,
      );
      expect(node.spaceType, SpaceType.personal);
    });

    test('uploadedBy defaults to null', () {
      const node = FileNode(
        id: '1',
        parentId: null,
        name: 'test.txt',
        isFolder: false,
        nodeType: 'FILE',
        normalizedPath: '/test.txt',
        sizeBytes: 100,
        updatedAt: null,
      );
      expect(node.uploadedBy, isNull);
    });

    test('shared file has correct spaceType', () {
      const node = FileNode(
        id: '1',
        parentId: null,
        name: 'movie.mkv',
        isFolder: false,
        nodeType: 'FILE',
        normalizedPath: '/movie.mkv',
        sizeBytes: 1024,
        updatedAt: null,
        spaceType: SpaceType.shared,
        uploadedBy: 'user-123',
      );
      expect(node.spaceType, SpaceType.shared);
      expect(node.uploadedBy, 'user-123');
    });
  });

  group('FileNodeDto', () {
    test('fromJson parses spaceType and uploadedBy', () {
      final json = {
        'id': '1',
        'name': 'movie.mkv',
        'nodeType': 'FILE',
        'normalizedPath': '/movie.mkv',
        'sizeBytes': 1024,
        'spaceType': 'SHARED',
        'uploadedBy': 'user-123',
      };
      final dto = FileNodeDto.fromJson(json);
      expect(dto.spaceType, SpaceType.shared);
      expect(dto.uploadedBy, 'user-123');
    });

    test('fromJson defaults spaceType to PERSONAL when missing', () {
      final json = {
        'id': '1',
        'name': 'movie.mkv',
        'nodeType': 'FILE',
        'normalizedPath': '/movie.mkv',
        'sizeBytes': 1024,
      };
      final dto = FileNodeDto.fromJson(json);
      expect(dto.spaceType, SpaceType.personal);
    });

    test('fromJson handles null uploadedBy', () {
      final json = {
        'id': '1',
        'name': 'movie.mkv',
        'nodeType': 'FILE',
        'normalizedPath': '/movie.mkv',
        'sizeBytes': 1024,
        'spaceType': 'PERSONAL',
        'uploadedBy': null,
      };
      final dto = FileNodeDto.fromJson(json);
      expect(dto.uploadedBy, isNull);
    });

    test('toDomain maps spaceType and uploadedBy correctly', () {
      final json = {
        'id': '1',
        'name': 'movie.mkv',
        'nodeType': 'FILE',
        'normalizedPath': '/movie.mkv',
        'sizeBytes': 1024,
        'spaceType': 'SHARED',
        'uploadedBy': 'user-123',
      };
      final dto = FileNodeDto.fromJson(json);
      final node = dto.toDomain();
      expect(node.spaceType, SpaceType.shared);
      expect(node.uploadedBy, 'user-123');
    });

    test('toDomain handles FOLDER nodeType', () {
      final json = {
        'id': '2',
        'name': 'movies',
        'nodeType': 'FOLDER',
        'normalizedPath': '/movies',
        'sizeBytes': 0,
        'spaceType': 'SHARED',
      };
      final dto = FileNodeDto.fromJson(json);
      final node = dto.toDomain();
      expect(node.isFolder, isTrue);
      expect(node.spaceType, SpaceType.shared);
    });
  });

  group('SharedSpaceUsage', () {
    test('usageRatio calculates correctly', () {
      const usage = SharedSpaceUsage(
        usedBytes: 5000,
        maxBytes: 10000,
        fileCount: 10,
      );
      expect(usage.usageRatio, 0.5);
    });

    test('usageRatio returns 0 when maxBytes is 0', () {
      const usage = SharedSpaceUsage(
        usedBytes: 5000,
        maxBytes: 0,
        fileCount: 10,
      );
      expect(usage.usageRatio, 0);
    });

    test('isUnlimited returns true when maxBytes is negative', () {
      const usage = SharedSpaceUsage(
        usedBytes: 5000,
        maxBytes: -1,
        fileCount: 10,
      );
      expect(usage.isUnlimited, isTrue);
    });

    test('isUnlimited returns false when maxBytes is positive', () {
      const usage = SharedSpaceUsage(
        usedBytes: 5000,
        maxBytes: 10000,
        fileCount: 10,
      );
      expect(usage.isUnlimited, isFalse);
    });

    test('usageRatio clamps to 0-1 range', () {
      const usage = SharedSpaceUsage(
        usedBytes: 15000,
        maxBytes: 10000,
        fileCount: 10,
      );
      expect(usage.usageRatio, 1.0);
    });
  });
}
