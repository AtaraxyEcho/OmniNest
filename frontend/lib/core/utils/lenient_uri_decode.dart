/// 宽容的百分号解码：只在确实出现 `%` 时尝试，失败则按原样返回。
///
/// `Uri.decodeComponent` 对两类输入会抛异常，而这两类在书籍内容里都很常见：
/// - 含裸非 ASCII 字符的路径（服务端下发的 EPUB `contentPath`、EPUB 内中文文件名）
///   抛 `ArgumentError`；
/// - 残缺或非法的百分号转义（作者手写的 `%`、被截断的 href）抛 `FormatException`。
///
/// 路径解析失败不应让整章或整张图不可用，因此调用方一律使用本函数，
/// 而不是各自写一份 try/catch（历史上三份实现都漏掉了 `ArgumentError`）。
String lenientDecodeComponent(String value) {
  if (!value.contains('%')) {
    return value;
  }
  try {
    return Uri.decodeComponent(value);
  } on Object {
    return value;
  }
}
