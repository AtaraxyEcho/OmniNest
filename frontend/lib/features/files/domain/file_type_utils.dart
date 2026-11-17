/// 文件预览类型分类。
enum FilePreviewType { image, video, audio, text, pdf, unsupported }

/// 根据 MIME 类型和文件名判断预览类型。
FilePreviewType classifyForPreview(String? mimeType, String fileName) {
  if (mimeType == null) return FilePreviewType.unsupported;
  if (mimeType.startsWith('image/')) return FilePreviewType.image;
  if (mimeType.startsWith('video/')) return FilePreviewType.video;
  if (mimeType.startsWith('audio/')) return FilePreviewType.audio;
  if (mimeType.startsWith('text/') ||
      mimeType == 'application/json' ||
      mimeType == 'application/xml') {
    return FilePreviewType.text;
  }
  if (mimeType == 'application/pdf') return FilePreviewType.pdf;
  return FilePreviewType.unsupported;
}
