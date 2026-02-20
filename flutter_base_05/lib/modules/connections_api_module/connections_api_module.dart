import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_interceptor/http_interceptor.dart';

import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/auth_manager.dart';
import '../../tools/logging/logger.dart';
import '../../utils/consts/config.dart';
import 'interceptor.dart';

class ConnectionsApiModule extends ModuleBase {
  static const bool LOGGING_SWITCH = false; // Set true for connectivity/API debug logs

  /// Retry once after this delay when a request fails with a transient error (e.g. public WiFi).
  static const Duration _retryDelay = Duration(milliseconds: 1500);
  static const int _maxAttempts = 2;

  final String baseUrl;
  AuthManager? _authManager;
  final Logger _logger = Logger();

  /// ✅ Use InterceptedClient instead of normal `http`
  final InterceptedClient client = InterceptedClient.build(
    interceptors: [AuthInterceptor()],
    requestTimeout: Duration(seconds: Config.httpRequestTimeout),
  );

  /// ✅ Constructor with module key and dependencies
  ConnectionsApiModule(this.baseUrl) : super('connections_api_module', dependencies: []);

  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    _authManager = AuthManager();
    _sendTestRequest();
  }

  /// Generate both HTTP and app deep links for a given path
  static Map<String, String> generateLinks(String path) {
    return {
      'http': 'https://example.com\$path',
      'app': 'dutch://\$path'
    };
  }

  /// Retries the [request] up to [_maxAttempts] times on transient errors (ClientException, Failed to fetch, timeout).
  /// Helps with flaky public WiFi where the first request often fails.
  Future<T> _withRetry<T>(Future<T> Function() request) async {
    int attempt = 0;
    while (true) {
      try {
        return await request();
      } catch (e) {
        attempt++;
        final details = e.toString().toLowerCase();
        final isTransient = e is http.ClientException ||
            details.contains('failed to fetch') ||
            details.contains('connection') ||
            details.contains('timeout') ||
            details.contains('socket');
        if (attempt < _maxAttempts && isTransient) {
          if (LOGGING_SWITCH) _logger.info('ConnectionsApi: retrying after transient error (attempt $attempt)');
          await Future.delayed(_retryDelay);
          continue;
        }
        rethrow;
      }
    }
  }

  /// Launch a URL, either in browser or app
  static Future<bool> launchUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      return await launcher.launchUrl(
        uri,
        mode: launcher.LaunchMode.externalApplication
      );
    } catch (e) {
      return false;
    }
  }

  /// ✅ GET Request without manually adding tokens (with retry on transient failures)
  Future<dynamic> sendGetRequest(String route) async {
    final url = Uri.parse('$baseUrl$route');
    if (LOGGING_SWITCH) _logger.info('ConnectionsApi: GET $route');

    try {
      final response = await _withRetry(() => client.get(url));
      return _processResponse(response, route: route);
    } catch (e) {
      return _handleError('GET', url, e);
    }
  }

  /// ✅ POST Request without manually adding tokens (with retry on transient failures)
  Future<dynamic> sendPostRequest(String route, Map<String, dynamic> data) async {
    final url = Uri.parse('$baseUrl$route');
    if (LOGGING_SWITCH) _logger.info('ConnectionsApi: POST $route');

    try {
      final response = await _withRetry(() => client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ));
      return _processResponse(response, route: route);
    } catch (e) {
      return _handleError('POST', url, e);
    }
  }

  /// ✅ Unified Request Method (with retry on transient failures)
  Future<dynamic> sendRequest(String route, {required String method, Map<String, dynamic>? data}) async {
    final url = Uri.parse('$baseUrl$route');
    if (LOGGING_SWITCH) _logger.info('ConnectionsApi: ${method.toUpperCase()} $route');
    http.Response response;

    try {
      final headers = {'Content-Type': 'application/json'};

      Future<http.Response> doRequest() async {
        switch (method.toUpperCase()) {
          case 'GET':
            return client.get(url);
          case 'POST':
            return client.post(url, headers: headers, body: jsonEncode(data ?? {}));
          case 'PUT':
            return client.put(url, headers: headers, body: jsonEncode(data ?? {}));
          case 'DELETE':
            return client.delete(url);
          default:
            throw Exception('❌ Unsupported HTTP method: $method');
        }
      }

      response = await _withRetry(doRequest);
      return _processResponse(response, route: route);
    } catch (e) {
      return _handleError(method, url, e);
    }
  }

  /// ✅ Process Server Response
  dynamic _processResponse(http.Response response, {String? route}) {
    final routeLabel = route ?? response.request?.url.path ?? '';

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (LOGGING_SWITCH) _logger.info('ConnectionsApi: $routeLabel → ${response.statusCode}');
      return jsonDecode(response.body);
    }

    if (LOGGING_SWITCH) {
      _logger.warning('ConnectionsApi: $routeLabel → ${response.statusCode} ${response.body.length > 200 ? response.body.substring(0, 200) + "…" : response.body}');
    }

    if (response.statusCode == 401) {
      // Don't clear tokens here - let AuthManager handle it through its own logic
      return {"message": "Session expired. Please log in again.", "error": "Unauthorized"};
    } else {
      try {
        final decodedResponse = jsonDecode(response.body);
        // Ensure we always have a message field for errors
        if (!decodedResponse.containsKey('message') && decodedResponse.containsKey('error')) {
          decodedResponse['message'] = decodedResponse['error'];
        }
        return decodedResponse;
      } catch (e) {
        return {
          "message": "An unexpected error occurred",
          "error": "Server error",
          "details": response.body
        };
      }
    }
  }

  /// ✅ Handle Errors with Detailed Logging
  /// Returns a user-facing [message] and [details] for debugging.
  Map<String, dynamic> _handleError(String method, Uri url, Object e) {
    if (LOGGING_SWITCH) _logger.error('ConnectionsApi: $method ${url.path} failed: $e', error: e);

    const String message =
        "Cannot reach server. If you're on public WiFi, try mobile data or a different network.";

    return {
      "message": message,
      "error": "$method request failed",
      "details": e.toString(),
    };
  }

  /// ✅ Send test request to verify connection
  void _sendTestRequest() {
    sendGetRequest('/health').then((response) {
      if (LOGGING_SWITCH) _logger.info('ConnectionsApi: health check OK');
    }).catchError((error) {
      if (LOGGING_SWITCH) _logger.error('ConnectionsApi: health check failed', error: error);
    });
  }
}