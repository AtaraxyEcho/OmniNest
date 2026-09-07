import 'package:flutter/material.dart';

/// 照片信息行：左标签右数值、底部分隔线（设计稿 Photo Info 行样式）。
///
/// 幻灯片 Info 面板与详情页信息侧栏共用；深色面板使用默认配色，
/// 亮色主题下由调用方传入主题化颜色。
class PhotoInfoRow extends StatelessWidget {
  const PhotoInfoRow({
    required this.label,
    required this.value,
    this.labelColor = const Color(0x59FFFFFF),
    this.valueColor = const Color(0xC0FFFFFF),
    this.dividerColor = const Color(0x14FFFFFF),
    super.key,
  });

  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;
  final Color dividerColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 11,
              letterSpacing: 0.04,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor,
                fontSize: 12,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
