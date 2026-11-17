String mediaCategoryFromMimeType(String? mimeType) {
  if (mimeType == null || mimeType.isEmpty) {
    return 'unknown';
  }
  return mimeType.split('/').first;
}
