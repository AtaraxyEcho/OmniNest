import 'dart:async';
import 'dart:math' show max, min;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/mobile_env_palette.dart';
import 'package:omninest/app/mobile_shell/mobile_environment_scope.dart';
import 'package:omninest/core/widgets/omni_icons.dart';
import 'package:omninest/features/backdrop/application/app_backdrop_controller.dart';
import 'package:omninest/features/backdrop/backdrop_ui.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop.dart';
import 'package:omninest/features/portal/application/weather_provider.dart';

/// 样例 `.weather-scene` 的固定带高。
const double _weatherSceneBandHeight = 250;

/// 面板最高占屏比。
///
/// 样例 `.weather-sheet` 写的是 `max-height: 91dvh`，实测本仓面板自然高度 821
/// 对样例 840（同 390 宽），比样例还紧一档——所以"展开过多"不是抄漏，而是 91dvh
/// 这个上限本身在手机上等于整屏。按最新指令压到 78dvh，抽屉上方留出
/// 约 186px 的壁纸与页面，保持"背景可见"这条原则。
const double _weatherSheetMaxHeightFactor = 0.78;

/// 天气详情底部面板（原型 WeatherDetail 逐值复刻）。
///
/// 结构：「{城市} · 本地天气」眉标 + 衬线天况标题 → 当前大字温度 →
/// 逐时横轨 → 2×2 指标格 → 三日预报 → 环境跟随尾注。7-9px 微型字号为
/// 样例签名密度，逐行登记 font_size_whitelist 豁免。
/// 面板不采样页面壁纸：样例用 `.weather-scene` 把同一张壁纸接进头部，
/// 但带外被 32% 墨遮罩压暗、带内被 82% 白玻璃提亮，纵向明度跨度大的
/// 壁纸会在面板圆角处留下实测 79-118 级的硬边（008 §十三），
/// 已定：抽屉按普通面板显示，不做壁纸联动。
/// 打开天气详情面板（样例 modal-layer 逐值复刻）。
///
/// 样例是全屏 fixed 层：blur(8px) 遮罩 + rgba(0,0,0,.45) 压暗淡入，
/// 面板从屏幕底部上滑锚定（覆盖顶栏/底栏）。宿主分支使用嵌套
/// Navigator，必须推入根 Navigator，否则遮罩只盖住分支视口、面板被
/// 压缩在底栏之上（内容顶部被裁）。
Future<void> showWeatherDetailSheet(
  BuildContext ownerContext, {
  required WeatherData weather,
}) {
  return Navigator.of(
    ownerContext,
    rootNavigator: true,
  ).push(_WeatherSheetRoute(weather: weather));
}

/// 天气面板路由：遮罩淡入（.2s）+ 面板上滑（.3s），均可用系统返回关闭。
class _WeatherSheetRoute extends PopupRoute<void> {
  _WeatherSheetRoute({required this.weather});

  final WeatherData weather;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => null;

  /// 保持下方页面存活：遮罩的 BackdropFilter 需要取到壳层环境像素。
  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    );
    final closeTooltip = MaterialLocalizations.of(context).closeButtonTooltip;
    // Material 提供正文默认样式：裸 PopupRoute 页面没有 Scaffold/Material 祖先时，
    // 文本会落到 MaterialApp 的兜底样式（黄色双下划线），抽屉内每个文字都带上它。
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // 遮罩：先 blur(8) 再压一层 modalScrim（暗态 45% 黑，浅态 32% 深绿黑）。
          Positioned.fill(
            child: Semantics(
              button: true,
              label: closeTooltip,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: DecoratedBoxTransition(
                      decoration: DecorationTween(
                        begin: const BoxDecoration(color: Colors.transparent),
                        end: BoxDecoration(color: context.env.modalScrim),
                      ).animate(curved),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(curved),
              child: _WeatherDragDismissSheet(weather: weather),
            ),
          ),
        ],
      ),
    );
  }
}

/// 面板容器：承接垂直拖拽（下拉关闭），替代系统 BottomSheet 手势。
class _WeatherDragDismissSheet extends StatelessWidget {
  const _WeatherDragDismissSheet({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    // 面板经 PopupRoute 推入，可能挂在 root navigator 上而拿不到首页子树的极性注册，
    // 所以自带一份。面板本身是画布面（样例 `.weather-sheet` 浅态是实色纸面），
    // 只有首页子树才是摄影面，因此这里不传 photographic。
    return MobileEnvironmentScope(
      child: GestureDetector(
        onVerticalDragEnd:
            (details) => _maybeDismiss(context, details.primaryVelocity),
        child: _WeatherDetailSheet(weather: weather),
      ),
    );
  }

  void _maybeDismiss(BuildContext context, double? velocity) {
    if (velocity != null && velocity > 240) {
      Navigator.of(context).pop();
    }
  }
}

class _WeatherDetailSheet extends StatelessWidget {
  const _WeatherDetailSheet({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final maxHeight =
        MediaQuery.sizeOf(context).height * _weatherSheetMaxHeightFactor;
    final location =
        weather.locationName.isNotEmpty
            ? weather.locationName
            : l10n.weatherSheetLocalFallback;
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    // 样例 --safe-bottom 是 max(12px, env(safe-area-inset-bottom))，
    // 抽屉底至少留 12。
    final safeBottom = max(12.0, MediaQuery.paddingOf(context).bottom);
    return Container(
      width: isWide ? 600 : double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.env.sheetSolid,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: context.env.line13)),
        boxShadow: [
          BoxShadow(
            color: context.env.sheetGlow,
            blurRadius: 60,
            offset: const Offset(0, -25),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _weatherSceneBandHeight,
            child: const _WeatherSceneBackdrop(),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: safeBottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 86),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(19, 24, 19, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n
                                    .weatherSheetLocationEyebrow(location)
                                    .toUpperCase(),
                                style: TextStyle(
                                  color: context.env.white70,
                                  // ignore: font_size_whitelist
                                  fontSize: 8,
                                  letterSpacing: 1.4,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                weather.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.env.ink,
                                  fontFamily: 'InstrumentSerif',
                                  // ignore: font_size_whitelist
                                  fontSize: 27,
                                  height: 1.05,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _WeatherCloseButton(
                          tooltip:
                              MaterialLocalizations.of(
                                context,
                              ).closeButtonTooltip,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WeatherCurrent(weather: weather),
                        if (weather.hourly.isNotEmpty)
                          _HourlyWeather(weather: weather),
                        _WeatherMetrics(weather: weather),
                        if (weather.daily.isNotEmpty)
                          _WeatherForecast(weather: weather),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            // 样例 .weather-environment span：6 圆点 + 0 0 8px 强调色光晕。
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: context.env.accent,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: context.env.accent,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.weatherSheetEnvironmentNote,
                                // 样例 .weather-environment：8px + 微型标签档墨色 + 浅层
                                // 声明的 line-height 1.45（暗态无人声明行高）。
                                style: TextStyle(
                                  color: context.env.microLabelInk,
                                  // ignore: font_size_whitelist
                                  fontSize: 8,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // 样例 .weather-environment margin 20 0 5：尾注再留 5 到主区内沿。
                        const SizedBox(height: 5),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 场景图头：壁纸 → 视频缩略图 → 打包默认壁纸三级兜底，恒有图。
///
/// 样例 `.weather-scene` 是面板顶部 250px 的绝对定位层：图按该盒
/// `object-fit: cover` 重裁并加 `saturate(.7) + opacity(.72)`，上面再压一层
/// `.weather-scene span`——暗态是 5% 到实底的渐变，浅态是平涂墨色 .14。
class _WeatherSceneBackdrop extends ConsumerWidget {
  const _WeatherSceneBackdrop();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset =
        ref.watch(appBackdropControllerProvider).asData?.value.selectedBackdrop;
    final sceneUrl =
        asset?.isVideo == true
            ? (asset?.thumbnailPath?.isNotEmpty == true
                ? asset!.thumbnailPath
                : null)
            : asset?.path;
    final bundled = Image.asset(
      bundledWallpaperAssetPathFor(AppBackdropSelectionTarget.mobile),
      fit: BoxFit.cover,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (sceneUrl == null || sceneUrl.isEmpty)
          bundled
        else
          Opacity(
            opacity: 0.72,
            child: ColorFiltered(
              colorFilter: ColorFilter.matrix(<double>[
                0.764, 0.215, 0.022, 0.000, 0.000, //
                0.064, 0.914, 0.022, 0.000, 0.000, //
                0.064, 0.215, 0.722, 0.000, 0.000, //
                0.000, 0.000, 0.000, 1.000, 0.000, //
              ]),
              child: Image.network(
                sceneUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => bundled,
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [context.env.sceneVeilTop, context.env.sceneVeilBottom],
            ),
          ),
        ),
      ],
    );
  }
}

/// 头部关闭钮：样例 `.icon-button`——48 圆形玻璃舱、1px line10 描边、
/// backdrop blur(16) 与默认 22 号 close 图元。
class _WeatherCloseButton extends StatelessWidget {
  const _WeatherCloseButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.env.iconButtonGlass,
              shape: BoxShape.circle,
              border: Border.all(color: context.env.line10),
            ),
            child: IconButton(
              tooltip: tooltip,
              onPressed: onPressed,
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                foregroundColor: context.env.ink,
                overlayColor: Colors.transparent,
                minimumSize: const Size.square(48),
              ),
              icon: OmniIcon(
                icon: OmniIcons.close,
                size: 22,
                color: context.env.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WeatherCurrent extends StatelessWidget {
  const _WeatherCurrent({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OmniIcon(
                icon: OmniIcons.weatherFor(int.tryParse(weather.icon) ?? -1),
                size: 35,
                color: context.env.ink,
              ),
              const SizedBox(width: 14),
              // 样例 weather-current strong：固定 74px 衬线，不随宽度缩放。
              Text(
                '${weather.temp}°',
                style: TextStyle(
                  color: context.env.ink,
                  fontFamily: 'InstrumentSerif',
                  // ignore: font_size_whitelist
                  fontSize: 74,
                  height: 0.9,
                  letterSpacing: -3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.weatherSheetFeelsLike(weather.feelsLike),
            // ignore: font_size_whitelist
            style: TextStyle(
              color: context.env.ink,
              // ignore: font_size_whitelist
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 3),
          // 描述必须由数据生成：原先这里是一句写死的 ARB（"晴好将持续到傍晚，
          // 夜间转凉、安静。"），下雨天也照播，属于假状态。
          if (_nearTermRange(l10n) case final String range)
            Text(
              range,
              // ignore: font_size_whitelist
              style: TextStyle(color: context.env.microLabelInk, fontSize: 10),
            ),
        ],
      ),
    );
  }

  /// 逐时轨覆盖的温区。少于两小时就没有区间可说，返回 null 让这一行整条消失。
  String? _nearTermRange(AppLocalizations l10n) {
    if (weather.hourly.length < 2) {
      return null;
    }
    final hours = weather.hourly.take(5).toList();
    final temps = hours.map((hour) => hour.temp);
    return l10n.weatherSheetHourRange(
      hours.length,
      temps.reduce(min),
      temps.reduce(max),
    );
  }
}

class _HourlyWeather extends StatelessWidget {
  const _HourlyWeather({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 样例固定 5 项、flex:1 均分（min-width 67），横向无间隙。
    final hours = weather.hourly.take(5).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final innerWidth = constraints.maxWidth;
        final slotWidth = max(67.0, innerWidth / hours.length);
        // 样例 .hourly-weather：margin 0 -20px 抵消主区 20 内边距，
        // 上下发丝线通铺面板整宽，自身 padding 16px 20px 保住内容内沿。
        return OverflowBox(
          alignment: Alignment.center,
          fit: OverflowBoxFit.deferToChild,
          minWidth: innerWidth + 40,
          maxWidth: innerWidth + 40,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: context.env.line13),
                bottom: BorderSide(color: context.env.line13),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var index = 0; index < hours.length; index++)
                    SizedBox(
                      width: slotWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            index == 0
                                ? l10n.weatherHourNow
                                : hours[index].displayTime,
                            // ignore: font_size_whitelist
                            style: TextStyle(
                              color: context.env.microLabelInk,
                              // ignore: font_size_whitelist
                              fontSize: 8,
                            ),
                          ),
                          const SizedBox(height: 10),
                          OmniIcon(
                            icon: OmniIcons.weatherByCode(hours[index].icon),
                            size: 19,
                            color: context.env.ink,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${hours[index].temp}°',
                            style: TextStyle(
                              color: context.env.ink,
                              // ignore: font_size_whitelist
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WeatherMetrics extends StatelessWidget {
  const _WeatherMetrics({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 后端 /weather/realtime 返回的风速与湿度已带单位
    // （WeatherService.java:481 那句 `+ " km/h"` / `+ "%"`），这里再拼一次
    // 就成了截图上的 "5 km/h km/h" 与 "81%%"。
    final cells = <(String, String, String, bool)>[
      (l10n.weatherMetricWind, weather.windSpeed, weather.windDir, false),
      // 样例湿度格有第三行（"Comfortable"），我们之前留空，格子比别的格空一截。
      (
        l10n.weatherMetricHumidity,
        weather.humidity,
        _humidityNote(l10n),
        false,
      ),
      (
        l10n.weatherMetricAirQuality,
        '${weather.aqi}',
        weather.aqiCategory,
        true,
      ),
      (l10n.weatherMetricSunset, weather.sunset, _sunsetDelta(context), false),
    ];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: Border.all(color: context.env.line13),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            for (var row = 0; row < 2; row++)
              IntrinsicHeight(
                child: Row(
                  children: [
                    for (var col = 0; col < 2; col++)
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 88),
                          decoration: BoxDecoration(
                            color: context.env.metricCell,
                            border: Border(
                              right:
                                  col == 0
                                      ? BorderSide(color: context.env.line13)
                                      : BorderSide.none,
                              bottom:
                                  row == 0
                                      ? BorderSide(color: context.env.line13)
                                      : BorderSide.none,
                            ),
                          ),
                          padding: const EdgeInsets.all(14),
                          child: _MetricCell(
                            label: cells[row * 2 + col].$1,
                            value: cells[row * 2 + col].$2,
                            detail: cells[row * 2 + col].$3,
                            highlight: cells[row * 2 + col].$4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 湿度格的说明行：按百分比给档位，不写死。后端返回的是 "62%" 这种带单位串。
  String _humidityNote(AppLocalizations l10n) {
    final percent = int.tryParse(
      weather.humidity.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    if (percent == null) {
      return '';
    }
    if (percent >= 70) {
      return l10n.weatherHumidityHumid;
    }
    if (percent <= 30) {
      return l10n.weatherHumidityDry;
    }
    return l10n.weatherHumidityComfortable;
  }

  String _sunsetDelta(BuildContext context) {
    final parsed = DateTime.tryParse(
      '${DateTime.now().toString().substring(0, 10)}T${weather.sunset}',
    );
    if (parsed == null) {
      return '';
    }
    final delta = parsed.difference(DateTime.now());
    if (delta.isNegative || delta.inMinutes < 1) {
      return '';
    }
    return AppLocalizations.of(context).weatherSunsetIn(delta.inMinutes);
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.value,
    required this.detail,
    required this.highlight,
  });

  final String label;
  final String value;
  final String detail;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    // 样例 weather-metrics 单元格：标签置顶，数值紧随（margin 5 0 1），
    // 明细沉在数值下，全部顶部打包而非撑满沉底。
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          // ignore: font_size_whitelist
          style: TextStyle(
            color: context.env.microLabelInk,
            // ignore: font_size_whitelist
            fontSize: 7,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            color: context.env.ink,
            fontFamily: 'InstrumentSerif',
            // ignore: font_size_whitelist
            fontSize: 22,
            height: 1,
          ),
        ),
        const SizedBox(height: 1),
        if (detail.isNotEmpty)
          Text(
            detail,
            // ignore: font_size_whitelist
            style: TextStyle(
              color:
                  highlight ? context.env.accentInk : context.env.microLabelInk,
              // ignore: font_size_whitelist
              fontSize: 8,
            ),
          ),
      ],
    );
  }
}

class _WeatherForecast extends StatelessWidget {
  const _WeatherForecast({required this.weather});

  final WeatherData weather;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 样例 days 固定 3 条（NEXT THREE DAYS）。
    final days = weather.daily.take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 42,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.weatherForecastTitle.toUpperCase(),
                    // ignore: font_size_whitelist
                    style: TextStyle(
                      color: context.env.microLabelInk,
                      // ignore: font_size_whitelist
                      fontSize: 8,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(_openEnvironmentSettings(context)),
                  style: TextButton.styleFrom(
                    foregroundColor: context.env.microLabelInk,
                    minimumSize: const Size(48, 40),
                    padding: EdgeInsets.zero,
                    // ignore: font_size_whitelist
                    textStyle: const TextStyle(fontSize: 8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.weatherSettingsAction),
                      // 样例标签与箭头之间是行内空格。
                      const SizedBox(width: 2),
                      OmniIcon(
                        icon: OmniIcons.chevron,
                        size: 15,
                        color: context.env.microLabelInk,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < days.length; index++)
            _ForecastRow(day: days[index], index: index),
        ],
      ),
    );
  }
}

class _ForecastRow extends StatelessWidget {
  const _ForecastRow({required this.day, required this.index});

  final WeatherDaily day;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final date = DateTime.tryParse(day.date);
    final label =
        index == 0
            ? l10n.weatherDayTomorrow
            : date == null
            ? day.date
            : // 不传 locale 时 DateFormat 走 Intl.defaultLocale（未设置即 en_US），
            // 中文界面下就出现「明天 / Saturday / Sunday」混排。
            DateFormat('EEEE', l10n.localeName).format(date);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.env.line07)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: context.env.ink,
                // ignore: font_size_whitelist
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Row(
              children: [
                OmniIcon(
                  icon: OmniIcons.weatherByCode(day.iconDay),
                  size: 18,
                  color: context.env.microLabelInk,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    day.textDay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // ignore: font_size_whitelist
                    style: TextStyle(
                      color: context.env.microLabelInk,
                      // ignore: font_size_whitelist
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              '${day.tempMax}°',
              style: TextStyle(
                color: context.env.ink,
                // ignore: font_size_whitelist
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 25,
            child: Text(
              '${day.tempMin}°',
              style: TextStyle(
                color: context.env.microLabelInk,
                // ignore: font_size_whitelist
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 关闭天气面板后打开视觉环境面板（跨 async gap 用根导航上下文）。
Future<void> _openEnvironmentSettings(BuildContext sheetContext) async {
  final rootElement =
      sheetContext.findRootAncestorStateOfType<NavigatorState>();
  showAppBackdropSettings(sheetContext);
  rootElement?.pop();
}
