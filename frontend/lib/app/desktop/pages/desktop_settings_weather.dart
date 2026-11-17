part of 'desktop_settings_page.dart';

/// Settings 内的天气位置与实时状态，位置偏好仍由 Portal 的共享控制器保存。
class _WeatherSettingsCard extends ConsumerStatefulWidget {
  const _WeatherSettingsCard();

  @override
  ConsumerState<_WeatherSettingsCard> createState() =>
      _WeatherSettingsCardState();
}

class _WeatherSettingsCardState extends ConsumerState<_WeatherSettingsCard> {
  final TextEditingController _city = TextEditingController();
  final FocusNode _cityFocus = FocusNode();
  Timer? _citySearchTimer;
  CancelToken? _citySearchToken;
  List<WeatherCitySuggestion> _citySuggestions = const [];
  String? _citySearchError;
  bool _citySearchBusy = false;
  int _citySearchGeneration = 0;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _city.text = ref.read(weatherLocationProvider).asData?.value ?? '';
  }

  @override
  void dispose() {
    _city.dispose();
    _cityFocus.dispose();
    _citySearchTimer?.cancel();
    _citySearchToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final location = ref.watch(weatherLocationProvider);
    final weather = ref.watch(realtimeWeatherProvider);
    ref.listen(weatherLocationProvider, (previous, next) {
      final value = next.asData?.value;
      if (next.hasValue && !_dirty && !_cityFocus.hasFocus) {
        _city.text = value ?? '';
      }
    });
    return _Card(
      title: l10n.weatherSettingsTitle,
      subtitle: l10n.weatherSettingsSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopTextField(
            keyName: 'desktop-weather-city',
            controller: _city,
            focusNode: _cityFocus,
            label: l10n.weatherSettingsLocation,
            hint: l10n.weatherSettingsLocationHint,
            prefixIcon: DesktopIcons.pin,
            onChanged: _onCityChanged,
          ),
          if (_citySearchBusy ||
              _citySearchError != null ||
              (_city.text.trim().length >= 2 && _citySuggestions.isNotEmpty))
            _buildCitySuggestions(context, l10n),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DesktopButton(
                label: l10n.weatherSettingsSaveLocation,
                icon: DesktopIcons.check,
                variant: DesktopButtonVariant.primary,
                busy: _saving,
                onPressed: _saving || !_dirty ? null : _saveLocation,
              ),
              DesktopButton(
                label: l10n.weatherSettingsUseDevice,
                icon: DesktopIcons.pin,
                variant: DesktopButtonVariant.soft,
                busy: _saving,
                onPressed:
                    _saving || (location.asData?.value == null && !_dirty)
                        ? null
                        : _useDeviceLocation,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: DesktopSkin.of(context).line),
          const SizedBox(height: 12),
          _WeatherCurrentStatus(weather: weather),
        ],
      ),
    );
  }

  void _onCityChanged(String value) {
    setState(() {
      _dirty = true;
      _citySearchError = null;
      _citySuggestions = const [];
    });
    _citySearchTimer?.cancel();
    _citySearchToken?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() => _citySearchBusy = false);
      return;
    }
    final generation = ++_citySearchGeneration;
    _citySearchTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_loadCitySuggestions(query, generation));
    });
  }

  Future<void> _loadCitySuggestions(String query, int generation) async {
    final token = CancelToken();
    _citySearchToken = token;
    setState(() => _citySearchBusy = true);
    final language =
        Localizations.localeOf(context).languageCode == 'en' ? 'en' : 'zh';
    try {
      final result = await ref
          .read(weatherApiProvider)
          .searchCities(query, language: language, cancelToken: token);
      if (!mounted || generation != _citySearchGeneration) return;
      setState(() {
        _citySuggestions = result;
        _citySearchError =
            result.isEmpty
                ? AppLocalizations.of(context).weatherCityNoMatches
                : null;
      });
    } on DioException catch (error) {
      if (!mounted ||
          generation != _citySearchGeneration ||
          CancelToken.isCancel(error)) {
        return;
      }
      setState(
        () =>
            _citySearchError =
                AppLocalizations.of(context).weatherCitySearchOffline,
      );
    } on Object {
      if (!mounted || generation != _citySearchGeneration) return;
      setState(
        () =>
            _citySearchError =
                AppLocalizations.of(context).weatherCitySearchOffline,
      );
    } finally {
      if (mounted && generation == _citySearchGeneration) {
        setState(() => _citySearchBusy = false);
      }
    }
  }

  Widget _buildCitySuggestions(BuildContext context, AppLocalizations l10n) {
    final skin = DesktopSkin.of(context);
    if (_citySearchBusy) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          l10n.weatherCitySearching,
          style: DesktopType.caption(skin.text3),
        ),
      );
    }
    if (_citySuggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_citySearchError!, style: DesktopType.caption(skin.text3)),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: skin.panelSolid,
        border: Border.all(color: skin.line),
        borderRadius: BorderRadius.circular(DesktopMetrics.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final city in _citySuggestions)
            InkWell(
              onTap:
                  () => setState(() {
                    _city.text = city.name;
                    _city.selection = TextSelection.collapsed(
                      offset: _city.text.length,
                    );
                    _citySuggestions = const [];
                    _citySearchError = null;
                    _dirty = true;
                  }),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Text(city.name, style: DesktopType.dense(skin.text2)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _saveLocation() async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(weatherLocationProvider.notifier).save(_city.text.trim());
      if (!mounted) return;
      setState(() => _dirty = false);
      ref.invalidate(realtimeWeatherProvider);
      showDesktopToast(
        context,
        l10n.weatherSettingsSaved,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.weatherSettingsSaveLocation, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _useDeviceLocation() async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(weatherLocationProvider.notifier).save(null);
      if (!mounted) return;
      setState(() {
        _city.clear();
        _dirty = false;
      });
      ref.invalidate(realtimeWeatherProvider);
      showDesktopToast(
        context,
        l10n.weatherSettingsSaved,
        icon: DesktopIcons.check,
      );
    } on Object catch (error) {
      if (mounted) {
        showDesktopToast(
          context,
          failureToast(l10n, l10n.weatherSettingsUseDevice, error),
          kind: DesktopToastKind.error,
          icon: DesktopIcons.info,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _WeatherCurrentStatus extends StatelessWidget {
  const _WeatherCurrentStatus({required this.weather});

  final AsyncValue<WeatherData> weather;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final skin = DesktopSkin.of(context);
    final value = weather.asData?.value;
    final message = switch (value?.status) {
      WeatherData.statusDisabled => l10n.weatherStatusDisabled,
      WeatherData.statusLocationNotFound => l10n.weatherStatusLocationMissing,
      WeatherData.statusUpstreamError => l10n.weatherStatusUpstreamFailed,
      _ when weather.hasError => l10n.weatherStatusUpstreamFailed,
      _ when weather.isLoading => l10n.weatherSettingsLoading,
      _ when value?.isDegraded == true => l10n.weatherStatusUpstreamFailed,
      _ => null,
    };
    return Row(
      children: [
        Icon(DesktopIcons.cloud, size: 18, color: skin.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.weatherSettingsCurrentConditions,
                style: DesktopType.rowTitle(skin.text),
              ),
              Text(
                message ??
                    '${value?.locationName.isNotEmpty == true ? value!.locationName : l10n.weatherSheetLocalFallback} · ${value?.text ?? ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DesktopType.caption(skin.text3),
              ),
            ],
          ),
        ),
        if (value != null && !value.isDegraded)
          Text('${value.temp}°', style: DesktopType.displaySm(skin.text)),
      ],
    );
  }
}
