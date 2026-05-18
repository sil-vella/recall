import 'package:http_interceptor/http_interceptor.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/managers/auth_manager.dart';

/// Header set on the single 401 retry to avoid refresh/sign-out loops.
const String _authRetryHeader = 'x-auth-retry';

class AuthInterceptor implements InterceptorContract {
  AuthManager? _authManager;
  InterceptedClient? _client;

  /// Called once after [InterceptedClient.build] so 401 responses can be retried.
  void attachClient(InterceptedClient client) {
    _client = client;
  }

  /// ✅ Initialize AuthManager
  void initialize() {
    _authManager = AuthManager();
  }

  @override
  bool shouldInterceptRequest() => true;

  @override
  bool shouldInterceptResponse() => true;

  @override
  Future<BaseRequest> interceptRequest({required BaseRequest request}) async {
    if (_authManager == null) {
      _authManager = AuthManager();
    }

    if (request.url.path.contains('/public/refresh') ||
        request.url.path.contains('/public/login') ||
        request.url.path.contains('/public/register')) {
      return request;
    }

    final token = await _authManager!.getCurrentValidToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return request;
  }

  @override
  Future<BaseResponse> interceptResponse({required BaseResponse response}) async {
    if (response is! http.Response || response.statusCode != 401) {
      return response;
    }
    if (_authManager == null) {
      _authManager = AuthManager();
    }

    final path = response.request?.url.path ?? '';
    final isRetry = response.request?.headers[_authRetryHeader] == 'true';

    Map<String, dynamic>? body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = null;
    }

    if (isRetry) {
      await _authManager!.handleHttp401Response(path, body: body);
      return response;
    }

    final refreshed = await _authManager!.handleHttp401Response(path, body: body);
    if (!refreshed) {
      return response;
    }

    final retryResponse = await _retryOnce(response.request);
    return retryResponse ?? response;
  }

  Future<http.Response?> _retryOnce(http.BaseRequest? original) async {
    if (_client == null || original == null) {
      return null;
    }
    if (original is! http.Request) {
      return null;
    }

    final headers = Map<String, String>.from(original.headers);
    headers[_authRetryHeader] = 'true';

    final token = await _authManager!.getAccessToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final retry = http.Request(original.method, original.url)
      ..headers.addAll(headers)
      ..bodyBytes = original.bodyBytes
      ..encoding = original.encoding;

    try {
      final streamed = await _client!.send(retry);
      return await http.Response.fromStream(streamed);
    } catch (_) {
      return null;
    }
  }
}
