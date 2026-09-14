/// 几何失效原因（方案 §73）：build / 事件只声明"什么变了"，
/// 提交时机由 Runtime 的 commit 边界决定（§42/§74）。
enum ReaderGeometryInvalidation {
  /// 视口尺寸变化。
  viewport,

  /// 文字缩放变化。
  textScale,

  /// 字体变化。
  font,

  /// 内容加载完成。
  contentLoaded,

  /// 分批测高更新。
  measurement,

  /// 图片测高更新。
  imageMeasurement,

  /// 窗口扩挂。
  windowExpansion,

  /// 窗口滑移。
  windowSlide,

  /// 章节收养。
  chapterAdoption,
}
