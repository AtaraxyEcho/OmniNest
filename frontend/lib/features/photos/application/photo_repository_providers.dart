import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/features/photos/data/photo_api.dart';
import 'package:omninest/features/photos/data/photo_repository_impl.dart';
import 'package:omninest/features/photos/domain/photo_repository.dart';

/// 照片 API 客户端。
final photoApiProvider = Provider<PhotoApi>((ref) {
  return PhotoApi(ref.watch(apiClientProvider));
});

/// 照片仓储。
final photoRepositoryProvider = Provider<PhotoRepository>((ref) {
  return PhotoRepositoryImpl(ref.watch(photoApiProvider));
});
