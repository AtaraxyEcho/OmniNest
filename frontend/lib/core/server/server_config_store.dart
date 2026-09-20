import 'package:omninest/core/server/server_config_store_base.dart';
import 'package:omninest/core/server/server_config_store_stub.dart'
    if (dart.library.io) 'package:omninest/core/server/server_config_store_io.dart'
    if (dart.library.html) 'package:omninest/core/server/server_config_store_web.dart'
    as platform_store;

export 'package:omninest/core/server/server_config_store_base.dart';

ServerConfigStore createServerConfigStore() {
  return platform_store.createServerConfigStore();
}
