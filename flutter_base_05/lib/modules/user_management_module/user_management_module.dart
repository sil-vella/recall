import 'package:flutter/material.dart';

import '../../core/00_base/module_base.dart';
import '../../core/managers/module_manager.dart';
import '../../modules/connections_api_module/connections_api_module.dart';

/// Core user management module. Exposes user search (and related APIs) for use by
/// any feature module (e.g. Dutch game for inviting users). Uses ConnectionsApiModule
/// to call the Python backend; JWT is sent automatically for /userauth/ routes.
class UserManagementModule extends ModuleBase {
  UserManagementModule()
      : super('user_management_module', dependencies: ['connections_api']);


  ConnectionsApiModule? _connectionsModule;
  @override
  void initialize(BuildContext context, ModuleManager moduleManager) {
    super.initialize(context, moduleManager);
    _connectionsModule = moduleManager.getModuleByType<ConnectionsApiModule>();
    
  }

  /// Search users by username (partial, case-insensitive). Calls POST /userauth/users/search.
  /// Returns a list of user maps (user_id, username, email, profile, etc.); passwords are excluded.
  /// Requires [usernameQuery] of at least 2 characters. Returns empty list on error or if module not ready.
  Future<List<Map<String, dynamic>>> searchByUsername(
    String usernameQuery, {
    int? limit,
  }) async {
    
    if (_connectionsModule == null) {
      
      return [];
    }
    final q = usernameQuery.trim();
    if (q.length < 2) {
      
      return [];
    }
    try {
      final body = <String, dynamic>{
        'username': q,
        if (limit != null) 'limit': limit.clamp(1, 50),
      };
      
      final response = await _connectionsModule!.sendPostRequest(
        '/userauth/users/search',
        body,
      );
      if (response is! Map) {
        
        return [];
      }
      if (response['success'] != true) {
        
        return [];
      }
      final users = response['users'];
      if (users is! List) {
        
        return [];
      }
      final list = users
          .map<Map<String, dynamic>>(
            (e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{},
          )
          .where((e) => e['user_id'] != null || e['_id'] != null)
          .toList();
      
      return list;
    } catch (e) {
      
      return [];
    }
  }
}
