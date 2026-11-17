/// 根据文件大小和策略常量计算最优分片大小。
/// 算法与后端 FileUploadSessionService.resolvePartSizeBytes() 一致：
/// 从 defaultPartSizeBytes 开始倍增，直到分片数 ≤ maxTotalParts，
/// 上限为 maxPartSizeBytes。
int calculatePartSizeBytes({
  required int fileSizeBytes,
  required int defaultPartSizeBytes,
  required int maxPartSizeBytes,
  required int maxTotalParts,
}) {
  if (fileSizeBytes <= defaultPartSizeBytes) {
    return fileSizeBytes;
  }
  int partSize = defaultPartSizeBytes;
  while (_totalParts(fileSizeBytes, partSize) > maxTotalParts &&
      partSize < maxPartSizeBytes) {
    partSize = (partSize * 2).clamp(0, maxPartSizeBytes);
  }
  return partSize;
}

int _totalParts(int fileSizeBytes, int partSizeBytes) {
  return (fileSizeBytes + partSizeBytes - 1) ~/ partSizeBytes;
}
