import 'package:omninest/core/auth/auth_session_store_base.dart';
import 'package:omninest/core/auth/auth_session_store_stub.dart'
    if (dart.library.io) 'package:omninest/core/auth/auth_session_store_io.dart'
    if (dart.library.js_interop) 'package:omninest/core/auth/auth_session_store_web.dart'
    as platform_store;

export 'package:omninest/core/auth/auth_session_store_base.dart';

AuthSessionStore createAuthSessionStore() {
  return platform_store.createAuthSessionStore();
}
