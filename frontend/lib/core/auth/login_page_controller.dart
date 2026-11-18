import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/auth/auth_models.dart';
import 'package:omninest/core/errors/app_exception.dart';

final loginPageControllerProvider =
    NotifierProvider.autoDispose<LoginPageController, LoginPageState>(
      LoginPageController.new,
    );

/// 登录提交错误：服务端或 AppException 自带最终文案，其余类别由
/// presentation 层映射为本地化文案，application 层不依赖 l10n。
sealed class LoginPageError {
  const LoginPageError();
}

/// 自带文案的错误：服务端返回的 message 或 AppException.message。
class LoginPageMessage extends LoginPageError {
  const LoginPageMessage(this.text);

  final String text;
}

/// 连接失败（网络不可达）。
class LoginPageConnectionError extends LoginPageError {
  const LoginPageConnectionError();
}

/// 请求已发出但失败。
class LoginPageRequestError extends LoginPageError {
  const LoginPageRequestError();
}

/// 未知异常兜底。
class LoginPageGenericError extends LoginPageError {
  const LoginPageGenericError();
}

/// 登录页流程状态：提交中标志、错误类别与认证续接挑战。
class LoginPageState {
  const LoginPageState({this.submitting = false, this.error, this.challenge});

  final bool submitting;
  final LoginPageError? error;
  final AuthChallenge? challenge;
}

/// 登录流程控制器：登录属业务状态，按分层规则由 application 层持有；
/// 导航与文案展示留在页面。
class LoginPageController extends Notifier<LoginPageState> {
  @override
  LoginPageState build() => const LoginPageState();

  /// 提交凭据登录。返回 true 表示登录完成（调用方负责导航）；
  /// false 表示已进入认证续接挑战或失败，详情已写入 state。
  Future<bool> submit({
    required String username,
    required String password,
  }) async {
    state = const LoginPageState(submitting: true);
    try {
      final result = await ref
          .read(authSessionProvider.notifier)
          .signInWithCredentials(username: username, password: password);
      if (result.requiresChallenge) {
        if (!ref.mounted) {
          return false;
        }
        state = LoginPageState(challenge: result.challenge);
        return false;
      }
      return true;
    } on DioException catch (error) {
      if (ref.mounted) {
        state = LoginPageState(error: _mapDioError(error));
      }
      return false;
    } on AppException catch (error) {
      if (ref.mounted) {
        state = LoginPageState(error: LoginPageMessage(error.message));
      }
      return false;
    } catch (_) {
      if (ref.mounted) {
        state = const LoginPageState(error: LoginPageGenericError());
      }
      return false;
    }
  }

  /// 首次改密完成后若服务端要求 2FA，则切到下一挑战，否则允许登录页导航。
  Future<bool> completeRequiredPasswordChange({
    required String challengeToken,
    required String newPassword,
  }) async {
    final currentChallenge = state.challenge;
    state = LoginPageState(submitting: true, challenge: currentChallenge);
    try {
      final result = await ref
          .read(authSessionProvider.notifier)
          .completeRequiredPasswordChange(
            challengeToken: challengeToken,
            newPassword: newPassword,
          );
      if (result.requiresChallenge) {
        if (!ref.mounted) {
          return false;
        }
        state = LoginPageState(challenge: result.challenge);
        return false;
      }
      if (ref.mounted) {
        state = const LoginPageState();
      }
      return true;
    } on DioException catch (error) {
      if (ref.mounted) {
        state = LoginPageState(
          error: _mapDioError(error),
          challenge: currentChallenge,
        );
      }
      return false;
    } on AppException catch (error) {
      if (ref.mounted) {
        state = LoginPageState(
          error: LoginPageMessage(error.message),
          challenge: currentChallenge,
        );
      }
      return false;
    } catch (_) {
      if (ref.mounted) {
        state = LoginPageState(
          error: const LoginPageGenericError(),
          challenge: currentChallenge,
        );
      }
      return false;
    }
  }

  /// 从 2FA 挑战退回账号密码表单。
  void exitChallenge() {
    state = const LoginPageState();
  }

  LoginPageError _mapDioError(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message != null && message.toString().isNotEmpty) {
        return LoginPageMessage(message.toString());
      }
    }
    if (error.type == DioExceptionType.connectionError) {
      return const LoginPageConnectionError();
    }
    return const LoginPageRequestError();
  }
}
