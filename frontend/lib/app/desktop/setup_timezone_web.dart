import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('Intl.DateTimeFormat')
@staticInterop
class _DateTimeFormat {
  external factory _DateTimeFormat([
    JSString? locales,
    _DateTimeFormatOptions? options,
  ]);
}

extension _DateTimeFormatMethods on _DateTimeFormat {
  external _ResolvedOptions resolvedOptions();

  external JSArray<JSAny?> formatToParts();
}

@JS()
@anonymous
@staticInterop
class _DateTimeFormatOptions {
  external factory _DateTimeFormatOptions({
    JSString? timeZone,
    JSString? timeZoneName,
  });
}

@JS()
@staticInterop
class _ResolvedOptions {}

extension _ResolvedOptionsProperties on _ResolvedOptions {
  external JSString get timeZone;
}

@JS('Intl.supportedValuesOf')
external JSArray<JSString> _supportedValuesOf(JSString key);

const List<String> _fallbackTimezones = <String>[
  'UTC',
  'Asia/Shanghai',
  'Asia/Tokyo',
  'Asia/Singapore',
  'Asia/Kolkata',
  'Europe/London',
  'Europe/Paris',
  'Europe/Berlin',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'Australia/Sydney',
];

String defaultSetupTimezone() {
  try {
    final timezone = _DateTimeFormat().resolvedOptions().timeZone.toDart;
    return availableSetupTimezones().contains(timezone) ? timezone : 'UTC';
  } on Object {
    return 'UTC';
  }
}

List<String> availableSetupTimezones() {
  try {
    final zones = _supportedValuesOf(
      'timeZone'.toJS,
    ).toDart.map((zone) => zone.toDart).toList(growable: false);
    if (zones.isEmpty) {
      return const <String>['UTC'];
    }
    return zones.contains('UTC') ? zones : <String>['UTC', ...zones];
  } on Object {
    return _fallbackTimezones;
  }
}

String setupTimezoneOffset(String timezone) {
  try {
    final formatter = _DateTimeFormat(
      'en'.toJS,
      _DateTimeFormatOptions(
        timeZone: timezone.toJS,
        timeZoneName: 'shortOffset'.toJS,
      ),
    );
    final parts = formatter.formatToParts().toDart;
    String? name;
    for (final part in parts) {
      final properties = part as JSObject;
      if ((properties.getProperty<JSString>('type'.toJS)).toDart ==
          'timeZoneName') {
        name = properties.getProperty<JSString>('value'.toJS).toDart;
        break;
      }
    }
    if (name == null || name.isEmpty) {
      return '';
    }
    return name.replaceFirst('GMT', 'UTC');
  } on Object {
    return '';
  }
}
