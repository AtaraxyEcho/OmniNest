import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/features/files/data/file_api.dart';
import 'package:omninest/features/files/data/file_repository_impl.dart';
import 'package:omninest/features/files/domain/file_repository.dart';

final fileApiProvider = Provider<FileApi>((ref) {
  final api = FileApi(ref.watch(apiClientProvider));
  ref.onDispose(api.close);
  return api;
});

final fileRepositoryProvider = Provider<FileRepository>((ref) {
  return FileRepositoryImpl(ref.watch(fileApiProvider));
});
