import 'package:flutter/material.dart';
import '../../tools/logging/logger.dart';
import '../00_base/service_base.dart';
import '../services/shared_preferences.dart';

class ServicesManager extends ChangeNotifier {
  static final Logger _log = Logger();
  static final ServicesManager _instance = ServicesManager._internal();
  factory ServicesManager() => _instance;
  ServicesManager._internal();

  final Map<String, ServicesBase> _services = {};

  Future<void> autoRegisterAllServices() async {
    // Register only default services
    await registerService('shared_pref', SharedPrefManager());
  }

  /// ✅ Allow registering multiple instances
  Future<void> registerService(String key, ServicesBase service) async {
    if (!_services.containsKey(key)) {
      _services[key] = service;
      await service.initialize();
      _log.info('✅ Service registered: $key');
      notifyListeners();
    }
  }

  /// ✅ Retrieve service by key
  T? getService<T extends ServicesBase>(String key) {
    final service = _services[key];
    if (service is T) {
      return service;
    }
    _log.error("❌ Service [$key] not found.");
    return null;
  }

  @override
  void dispose() {
    for (var service in _services.values) {
      service.dispose();
    }
    _services.clear();
    super.dispose();
  }
}
