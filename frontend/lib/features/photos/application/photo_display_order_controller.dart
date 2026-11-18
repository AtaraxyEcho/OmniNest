import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/log/dev_log.dart';
import 'package:omninest/features/photos/domain/photo.dart';
import 'package:shared_preferences/shared_preferences.dart';

final photoDisplayOrderProvider = NotifierProvider.autoDispose<
  PhotoDisplayOrderController,
  Map<String, List<String>>
>(PhotoDisplayOrderController.new);

class PhotoDisplayOrderController extends Notifier<Map<String, List<String>>> {
  static const String _preferencesKey = 'photos.display_order.v1';

  Future<void> _writeTail = Future<void>.value();
  String? _userId;
  int _revision = 0;

  @override
  Map<String, List<String>> build() {
    _userId = ref.watch(
      authSessionProvider.select((session) => session.value?.user?.id),
    );
    final revision = ++_revision;
    final userId = _userId;
    if (userId != null && userId.isNotEmpty) {
      unawaited(_restore(userId, revision));
    }
    return const <String, List<String>>{};
  }

  Future<void> saveOrder(String contextKey, List<String> ids) async {
    final userId = _userId;
    if (!ref.mounted || userId == null || userId.isEmpty || ids.isEmpty) {
      return;
    }
    final next = Map<String, List<String>>.of(state)
      ..[contextKey] = List<String>.unmodifiable(ids);
    state = Map<String, List<String>>.unmodifiable(next);
    final revision = ++_revision;
    await _persist(userId, revision, next);
  }

  Future<void> resetOrder(String contextKey) async {
    final userId = _userId;
    if (!ref.mounted || userId == null || userId.isEmpty) return;
    final next = Map<String, List<String>>.of(state)..remove(contextKey);
    state = Map<String, List<String>>.unmodifiable(next);
    final revision = ++_revision;
    await _persist(userId, revision, next);
  }

  Future<void> _restore(String userId, int revision) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_key(userId));
      if (!ref.mounted || revision != _revision || userId != _userId) return;
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final orders = <String, List<String>>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is List) {
          orders[entry.key] = value.whereType<String>().toList(growable: false);
        }
      }
      if (!ref.mounted || revision != _revision || userId != _userId) return;
      state = Map<String, List<String>>.unmodifiable(orders);
    } on Object catch (error) {
      if (ref.mounted && revision == _revision && userId == _userId) {
        devLog('Could not restore photo display order: ${error.runtimeType}');
      }
    }
  }

  Future<void> _persist(
    String userId,
    int revision,
    Map<String, List<String>> orders,
  ) {
    final serialized = jsonEncode(orders);
    final write = _writeTail.then<void>(
      (_) => _write(userId, revision, serialized),
      onError: (Object _) => _write(userId, revision, serialized),
    );
    _writeTail = write;
    return write;
  }

  Future<void> _write(String userId, int revision, String serialized) async {
    if (!ref.mounted || revision != _revision || userId != _userId) return;
    final preferences = await SharedPreferences.getInstance();
    if (!ref.mounted || revision != _revision || userId != _userId) return;
    final saved = await preferences.setString(_key(userId), serialized);
    if (!saved) {
      throw StateError('Photo display order could not be saved');
    }
  }

  String _key(String userId) => '$_preferencesKey.$userId';
}

String photoOrderContextForDay(DateTime? day) {
  if (day == null) return 'library:unknown';
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  return 'library:${day.year}-$month-$date';
}

List<PhotoItem> applyPhotoDisplayOrder(
  List<PhotoItem> photos,
  List<String>? order,
) {
  if (order == null || order.isEmpty) return photos;
  final rank = <String, int>{
    for (var index = 0; index < order.length; index++) order[index]: index,
  };
  final entries = photos.asMap().entries.toList(growable: false);
  entries.sort((left, right) {
    final leftRank = rank[left.value.id] ?? order.length + left.key;
    final rightRank = rank[right.value.id] ?? order.length + right.key;
    return leftRank.compareTo(rightRank);
  });
  return entries.map((entry) => entry.value).toList(growable: false);
}

List<PhotoItem> applyPhotoLibraryDisplayOrder(
  List<PhotoItem> photos,
  Map<String, List<String>> orders,
) {
  final groups = <DateTime?, List<PhotoItem>>{};
  for (final photo in photos) {
    final date = photo.dateTaken ?? photo.createdAt;
    final day = date == null ? null : DateTime(date.year, date.month, date.day);
    groups.putIfAbsent(day, () => <PhotoItem>[]).add(photo);
  }
  return groups.entries
      .expand(
        (entry) => applyPhotoDisplayOrder(
          entry.value,
          orders[photoOrderContextForDay(entry.key)],
        ),
      )
      .toList(growable: false);
}

List<String> movePhotoDisplayOrder({
  required List<String> order,
  required String draggedId,
  required String targetId,
  required Set<String> selectedIds,
}) {
  final moving =
      selectedIds.contains(draggedId) && selectedIds.length > 1
          ? order.where(selectedIds.contains).toList(growable: false)
          : <String>[draggedId];
  if (!order.contains(draggedId) || moving.isEmpty) return order;
  final base = order
      .where((id) => id == draggedId || !moving.contains(id))
      .toList(growable: false);
  final from = base.indexOf(draggedId);
  final target = base.indexOf(targetId);
  if (from < 0 || target < 0 || from == target) return order;
  final next = List<String>.of(base)..removeAt(from);
  next.insert(target, draggedId);
  final expanded = <String>[];
  for (final id in next) {
    if (id == draggedId) {
      expanded.addAll(moving);
    } else {
      expanded.add(id);
    }
  }
  return List<String>.unmodifiable(expanded);
}
