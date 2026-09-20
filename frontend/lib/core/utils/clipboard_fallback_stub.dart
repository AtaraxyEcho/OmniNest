/// 平台剪贴板回退桩：非 Web 平台没有 DOM 回退能力。
bool clipboardFallbackCopy(String text) {
  return false;
}
