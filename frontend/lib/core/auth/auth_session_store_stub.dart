import 'package:omninest/core/auth/auth_session_store_base.dart';

AuthSessionStore createAuthSessionStore() {
  return MemoryAuthSessionStore();
}
