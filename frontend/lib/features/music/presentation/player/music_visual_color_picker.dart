import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';

/// 编辑视觉窗口的歌词颜色字段：点击色块打开调色盘弹窗。
///
/// 弹窗提供主流音乐应用风格的预设色板、当前主题派生色、
/// 二维饱和度亮度取色面、色相条与 HEX 输入。
class MusicVisualColorField extends StatelessWidget {
  const MusicVisualColorField({
    super.key,
    required this.palette,
    required this.label,
    required this.value,
    required this.defaultValue,
    required this.onChanged,
  });

  final MusicImmersivePalette palette;
  final String label;
  final Color value;

  /// 「恢复默认色」使用的字段默认值。
  final Color defaultValue;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: TextStyle(color: palette.text)),
      trailing: Semantics(
        button: true,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _openPicker(context),
          child: Container(
            width: 42,
            height: 30,
            decoration: BoxDecoration(
              color: value,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.34)),
            ),
          ),
        ),
      ),
      onTap: () => _openPicker(context),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final selected = await showDialog<Color>(
      context: context,
      builder:
          (context) => _VisualColorDialog(
            palette: palette,
            title: label,
            initialColor: value,
            defaultValue: defaultValue,
          ),
    );
    if (selected != null) {
      onChanged(selected);
    }
  }
}

/// 预设色板：白灰、黑金、暖色、冷色四组主流音乐应用常用色。
const List<Color> _visualPresetColors = <Color>[
  // 白灰系
  Color(0xFFFFFFFF),
  Color(0xFFDCE6E8),
  Color(0xFFA8B8BD),
  Color(0xFF8DA2A7),
  // 金色系（黑金经典）
  Color(0xFFF2D986),
  Color(0xFFD9B36C),
  Color(0xFFB08D57),
  // 暖色系
  Color(0xFFF2C55C),
  Color(0xFFF0A46B),
  Color(0xFFE87878),
  Color(0xFFDD4A4A),
  Color(0xFFE97FA9),
  // 冷色系
  Color(0xFF72D6C9),
  Color(0xFF31C27C),
  Color(0xFF83C982),
  Color(0xFF58B7D9),
  Color(0xFF4A90D9),
  Color(0xFF6F92E8),
  Color(0xFFA78BE8),
];

class _VisualColorDialog extends StatefulWidget {
  const _VisualColorDialog({
    required this.palette,
    required this.title,
    required this.initialColor,
    required this.defaultValue,
  });

  final MusicImmersivePalette palette;
  final String title;
  final Color initialColor;
  final Color defaultValue;

  @override
  State<_VisualColorDialog> createState() => _VisualColorDialogState();
}

class _VisualColorDialogState extends State<_VisualColorDialog> {
  late HSVColor _color;
  late final TextEditingController _hexController;
  late final FocusNode _hexFocusNode;
  bool _hexEditing = false;

  @override
  void initState() {
    super.initState();
    _color = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(text: _formatHex(_color.toColor()));
    _hexFocusNode = FocusNode();
    _hexFocusNode.addListener(_handleHexFocusChange);
  }

  @override
  void dispose() {
    _hexFocusNode.removeListener(_handleHexFocusChange);
    _hexFocusNode.dispose();
    _hexController.dispose();
    super.dispose();
  }

  void _handleHexFocusChange() {
    final focused = _hexFocusNode.hasFocus;
    if (_hexEditing && !focused) {
      _hexController.text = _formatHex(_color.toColor());
    }
    _hexEditing = focused;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      backgroundColor: const Color(0xFF111A20),
      title: Text(widget.title, style: TextStyle(color: widget.palette.text)),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCaption(l10n.musicVisualizerColorPreset),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _visualPresetColors.map(_buildSwatch).toList(),
              ),
              const SizedBox(height: 12),
              _buildCaption(l10n.musicVisualizerColorTheme),
              Wrap(
                spacing: 10,
                children: [
                  _buildSwatch(widget.palette.accent),
                  _buildSwatch(widget.palette.accentAlt),
                  _buildSwatch(widget.palette.text),
                  _buildSwatch(widget.palette.surfaceStrong),
                ],
              ),
              const SizedBox(height: 16),
              _buildCaption(l10n.musicVisualizerColorCustom),
              _VisualSvPanel(
                color: _color,
                semanticLabel: l10n.musicVisualizerColorCustom,
                onChanged: _applyColor,
              ),
              const SizedBox(height: 10),
              _VisualHueBar(
                color: _color,
                semanticLabel: l10n.musicVisualizerColorHue,
                onChanged: (hue) => _applyColor(_color.withHue(hue)),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _color.toColor(),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.34),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('music-visual-color-hex'),
                      controller: _hexController,
                      focusNode: _hexFocusNode,
                      style: TextStyle(color: widget.palette.text),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[#0-9a-fA-F]'),
                        ),
                        LengthLimitingTextInputFormatter(7),
                      ],
                      decoration: InputDecoration(
                        labelText: l10n.musicVisualizerColorHex,
                        labelStyle: TextStyle(
                          color: widget.palette.text.withValues(alpha: 0.68),
                        ),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: _handleHexChanged,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: l10n.musicVisualizerColorResetDefault,
                    onPressed:
                        () => _applyColor(
                          HSVColor.fromColor(widget.defaultValue),
                        ),
                    icon: Icon(
                      Icons.restart_alt_rounded,
                      color: widget.palette.text,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_color.toColor()),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }

  Widget _buildCaption(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: widget.palette.text.withValues(alpha: 0.62),
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildSwatch(Color preset) {
    final selected = preset.toARGB32() == _color.toColor().toARGB32();
    return Tooltip(
      message: _formatHex(preset),
      child: Semantics(
        button: true,
        selected: selected,
        label: _formatHex(preset),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _applyColor(HSVColor.fromColor(preset)),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: preset,
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    selected
                        ? widget.palette.text
                        : Colors.white.withValues(alpha: 0.22),
                width: selected ? 3 : 1,
              ),
            ),
            child:
                selected
                    ? Icon(
                      Icons.check_rounded,
                      size: 15,
                      color:
                          preset.computeLuminance() > 0.52
                              ? Colors.black
                              : Colors.white,
                    )
                    : null,
          ),
        ),
      ),
    );
  }

  void _applyColor(HSVColor next) {
    setState(() => _color = next);
    if (!_hexEditing) {
      _hexController.text = _formatHex(next.toColor());
    }
  }

  void _handleHexChanged(String text) {
    final parsed = _parseHex(text);
    if (parsed == null) {
      return;
    }
    setState(() => _color = HSVColor.fromColor(parsed));
  }

  static Color? _parseHex(String input) {
    var text = input.trim();
    if (text.startsWith('#')) {
      text = text.substring(1);
    }
    if (text.length != 6) {
      return null;
    }
    final value = int.tryParse(text, radix: 16);
    if (value == null) {
      return null;
    }
    return Color(0xFF000000 | value);
  }

  static String _formatHex(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

/// 二维取色面：横轴饱和度、纵轴亮度，中间圆点为当前取值。
class _VisualSvPanel extends StatelessWidget {
  const _VisualSvPanel({
    required this.color,
    required this.semanticLabel,
    required this.onChanged,
  });

  final HSVColor color;
  final String semanticLabel;
  final ValueChanged<HSVColor> onChanged;

  static const double _thumbRadius = 9;

  @override
  Widget build(BuildContext context) {
    final hueColor = color.withSaturation(1).withValue(1).toColor();
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        key: const ValueKey('music-visual-color-sv-panel'),
        width: double.infinity,
        height: 150,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              void update(Offset local) {
                final saturation = (local.dx / constraints.maxWidth).clamp(
                  0.0,
                  1.0,
                );
                final value =
                    1 - (local.dy / constraints.maxHeight).clamp(0.0, 1.0);
                onChanged(color.withSaturation(saturation).withValue(value));
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => update(details.localPosition),
                onPanStart: (details) => update(details.localPosition),
                onPanUpdate: (details) => update(details.localPosition),
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: hueColor)),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.white,
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left:
                          (color.saturation * constraints.maxWidth -
                              _thumbRadius),
                      top:
                          ((1 - color.value) * constraints.maxHeight -
                              _thumbRadius),
                      child: IgnorePointer(
                        child: Container(
                          width: _thumbRadius * 2,
                          height: _thumbRadius * 2,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 色相条：彩虹渐变轨道，两端闭合。
class _VisualHueBar extends StatelessWidget {
  const _VisualHueBar({
    required this.color,
    required this.semanticLabel,
    required this.onChanged,
  });

  final HSVColor color;
  final String semanticLabel;
  final ValueChanged<double> onChanged;

  static const List<Color> _hueStops = <Color>[
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  static const double _thumbDiameter = 16;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        key: const ValueKey('music-visual-color-hue-bar'),
        width: double.infinity,
        height: 26,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: LayoutBuilder(
            builder: (context, constraints) {
              void update(Offset local) {
                final hue =
                    (local.dx / constraints.maxWidth).clamp(0.0, 1.0) * 360;
                onChanged(hue);
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => update(details.localPosition),
                onPanStart: (details) => update(details.localPosition),
                onPanUpdate: (details) => update(details.localPosition),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: _hueStops,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left:
                          (color.hue / 360 * constraints.maxWidth -
                              _thumbDiameter / 2),
                      top: (constraints.maxHeight - _thumbDiameter) / 2,
                      child: IgnorePointer(
                        child: Container(
                          width: _thumbDiameter,
                          height: _thumbDiameter,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                color.withSaturation(1).withValue(1).toColor(),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
