import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_interceptor/http_interceptor.dart';

import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/auth_manager.dart';
import '../../utils/consts/config.dart';
import 'interceptor.dart';

class ConnectionsApiModule extends ModuleBase {
  final String baseUrl;
  AuthManager? _authManager;

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
      'app': 'recall://\$path'
    };
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

  /// ✅ GET Request without manually adding tokens
  Future<dynamic> sendGetRequest(String route) async {
    final url = Uri.parse('$baseUrl$route');

    try {
      final response = await client.get(url);
      return _processResponse(response);
    } catch (e) {
      return _handleError('GET', url, e);
    }
  }

  /// ✅ POST Request without manually adding tokens
  Future<dynamic> sendPostRequest(String route, Map<String, dynamic> data) async {
    final url = Uri.parse('$baseUrl$route');

    try {
      final response = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      return _processResponse(response);
    } catch (e) {
      return _handleError('POST', url, e);
    }
  }

  /// ✅ Unified Request Method
  Future<dynamic> sendRequest(String route, {required String method, Map<String, dynamic>? data}) async {
    final url = Uri.parse('$baseUrl$route');
    http.Response response;

    try {
      final headers = {'Content-Type': 'application/json'};
      
      switch (method.toUpperCase()) {
        case 'GET':
          response = await client.get(url);
          break;
        case 'POST':
          response = await client.post(url, headers: headers, body: jsonEncode(data ?? {}));
          break;
        case 'PUT':
          response = await client.put(url, headers: headers, body: jsonEncode(data ?? {}));
          break;
        case 'DELETE':
          response = await client.delete(url);
          break;
        default:
          throw Exception('❌ Unsupported HTTP method: $method');
      }

      return _processResponse(response);
    } catch (e) {
      return _handleError(method, url, e);
    }
  }

  /// ✅ Process Server Response
  dynamic _processResponse(http.Response response) {
    if (response.body.isNotEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
      } else {
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
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
  Map<String, dynamic> _handleError(String method, Uri url, Object e) {
    return {
      "message": "Failed to connect to server. Please check your internet connection.",
      "error": "$method request failed",
      "details": e.toString()
    };
  }

  /// ✅ Send test request to verify connection
  void _sendTestRequest() {
    sendGetRequest('/health').then((response) {
    }).catchError((error) {
    });
  }
}