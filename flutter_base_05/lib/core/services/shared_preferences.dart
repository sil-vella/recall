import 'dart:convert'; // ✅ Import for JSON encoding/decoding
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../tools/logging/logger.dart';
import '../00_base/service_base.dart';
import '../managers/services_manager.dart'; // Import ServicesManager

class SharedPrefManager extends ServicesBase {
  static final Logger _log = Logger(); // ✅ Use a static logger for static methods
  static final SharedPrefManager _instance = SharedPrefManager._internal();
  SharedPreferences? _prefs;

  SharedPrefManager._internal();

  factory SharedPrefManager() => _instance;

  @override
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _log.info('✅ SharedPreferences initialized.');
    _logAllSharedPreferences();
  }

  /// ✅ Get all keys stored in SharedPreferences
  Set<String> getKeys() {
    return _prefs?.getKeys() ?? {};
  }

  /// ✅ Generic method to get a value by key
  dynamic get(String key) {
    return _prefs?.get(key);
  }

  /// ✅ Logs all stored SharedPreferences data at startup
  void _logAllSharedPreferences() {
    final allKeys = _prefs?.getKeys() ?? {};

    if (allKeys.isEmpty) {
      _log.info("⚠️ SharedPreferences is empty.");
      return;
    }

    _log.info("📜 SharedPreferences Data Dump:");
    for (String key in allKeys) {
      final value = _prefs?.get(key);
      if (value is String && _isJson(value)) {
        _log.info("📌 $key: ${jsonDecode(value)} (List<String>)");
      } else {
        _log.info("📌 $key: $value");
      }
    }
  }

  /// ✅ Helper to check if a string is valid JSON (for lists stored as JSON strings)
  bool _isJson(String str) {
    try {
      jsonDecode(str);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------- CREATE METHODS (Only Set If Key Doesn't Exist) -------------------

  Future<void> createString(String key, String value) async {
    if (_prefs?.containsKey(key) == true) {
      _log.info('⚠️ Skipped creating String: $key already exists with value ${_prefs?.getString(key)}');
      return;
    }
    await setString(key, value);
  }

  Future<void> createInt(String key, int value) async {
    if (_prefs?.containsKey(key) == true) {
      _log.info('⚠️ Skipped creating Int: $key already exists with value ${_prefs?.getInt(key)}');
      return;
    }
    await setInt(key, value);
  }

  Future<void> createBool(String key, bool value) async {
    if (_prefs?.containsKey(key) == true) {
      _log.info('⚠️ Skipped creating Bool: $key already exists with value ${_prefs?.getBool(key)}');
      return;
    }
    await setBool(key, value);
  }

  Future<void> createDouble(String key, double value) async {
    if (_prefs?.containsKey(key) == true) {
      _log.info('⚠️ Skipped creating Double: $key already exists with value ${_prefs?.getDouble(key)}');
      return;
    }
    await setDouble(key, value);
  }

  Future<void> createStringList(String key, List<String> value) async {
    if (_prefs?.containsKey(key) == true) {
      _log.info('⚠️ Skipped creating String List: $key already exists with value ${getStringList(key)}');
      return;
    }
    await setStringList(key, value);
  }

  // ------------------- SETTER METHODS (Always Set the Value) -------------------

  Future<void> setString(String key, String value) async {
    await _prefs?.setString(key, value);
    _log.info('✅ Set String: $key = $value');
  }

  Future<void> setInt(String key, int value) async {
    await _prefs?.setInt(key, value);
    _log.info('✅ Set Int: $key = $value');
  }

  Future<void> setBool(String key, bool value) async {
    await _prefs?.setBool(key, value);
    _log.info('✅ Set Bool: $key = $value');
  }

  Future<void> setDouble(String key, double value) async {
    await _prefs?.setDouble(key, value);
    _log.info('✅ Set Double: $key = $value');
  }

  /// ✅ Store list as JSON string safely
  Future<void> setStringList(String key, List<String> value) async {
    if (value.isEmpty) {
      _log.error("⚠️ Attempted to store an empty list in SharedPreferences: $key");
    }
    await _prefs?.setString(key, jsonEncode(value));
    _log.info('✅ Set String List: $key = $value');
  }


  // ------------------- GETTER METHODS -------------------

  String? getString(String key) => _prefs?.getString(key);
  int? getInt(String key) => _prefs?.getInt(key);
  bool? getBool(String key) => _prefs?.getBool(key);
  double? getDouble(String key) => _prefs?.getDouble(key);

  /// ✅ Retrieve list by decoding JSON string
  /// ✅ Retrieve list by decoding JSON string safely
  List<String> getStringList(String key) {
    String? jsonString = _prefs?.getString(key);

    if (jsonString == null || jsonString.isEmpty) {
      _log.error("⚠️ SharedPreferences contains empty data for key: $key. Returning empty list.");
      return [];
    }

    try {
      return List<String>.from(jsonDecode(jsonString)); // ✅ Convert JSON back to List<String>
    } catch (e) {
      _log.error("❌ JSON decoding error in getStringList for key: $key | Error: $e");
      return []; // ✅ Return an empty list instead of crashing
    }
  }


  // ------------------- UTILITY METHODS -------------------

  Future<void> remove(String key) async {
    await _prefs?.remove(key);
    _log.info('🗑️ Removed key: $key');
  }

  Future<void> clear() async {
    await _prefs?.clear();
    _log.info('🗑️ Cleared all preferences');
  }

  @override
  void dispose() {
    super.dispose();
    _log.info('🛑 SharedPrefManager disposed.');
  }
}
