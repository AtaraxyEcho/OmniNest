import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/app.dart';
import 'package:omninest/app/bootstrap.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';

void main() {
  bootstrap(
    (data) => ProviderScope(
      overrides: [appBootstrapDataProvider.overrideWithValue(data)],
      child: const OmniNestApp(),
    ),
  );
}
