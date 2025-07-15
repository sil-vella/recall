import 'package:http_interceptor/http_interceptor.dart';
import 'package:http/http.dart';
import '../../core/managers/auth_manager.dart';

/// class AuthInterceptor - Handles authentication and authorization
///
/// Handles authentication and authorization
///
/// Example:
/// ```dart
/// final authinterceptor = AuthInterceptor();
/// ```
///
class AuthInterceptor implements InterceptorContract {
  AuthManager? _authManager;

  /// ✅ Initialize AuthManager
  void initialize() {
    _authManager = AuthManager();
  }

  /// ✅ Decide if the request should be intercepted
  @override
  bool shouldInterceptRequest() => true;

  /// ✅ Decide if the response should be intercepted
  @override
  bool shouldInterceptResponse() => true;

  /// ✅ Modify the request to add an authorization token using AuthManager
  @override
  Future<BaseRequest> interceptRequest({required BaseRequest request}) async {
    if (_authManager == null) {
      _authManager = AuthManager();
    }
    
    // Use AuthManager to get current valid token
    final token = await _authManager!.getCurrentValidToken();
    if (token != null) {
      request.headers["Authorization"] = "Bearer $token"; // ✅ Auto-add token via AuthManager
    }
    return request;
  }

  /// ✅ Modify the response if needed (e.g., refresh token on 401)
  @override
  Future<BaseResponse> interceptResponse({required BaseResponse response}) async {
    if (response is Response && response.statusCode == 401) {
      // ✅ Handle Unauthorized using AuthManager
      if (_authManager == null) {
        _authManager = AuthManager();
      }
      await _authManager!.clearTokens();
    }
    return response;
  }
}
