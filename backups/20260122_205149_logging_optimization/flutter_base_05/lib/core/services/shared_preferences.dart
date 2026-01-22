import 'dart:convert'; // ✅ Import for JSON encoding/decoding
import 'package:shared_preferences/shared_preferences.dart';
import '../00_base/service_base.dart';

class SharedPrefManager extends ServicesBase {
  static final SharedPrefManager _instance = SharedPrefManager._internal();
  SharedPreferences? _prefs;

  SharedPrefManager._internal();

  factory SharedPrefManager() => _instance;

  @override
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// ✅ Get all keys stored in SharedPreferences
  Set<String> getKeys() {
    return _prefs?.getKeys() ?? {};
  }

  /// ✅ Generic method to get a value by key
  dynamic get(String key) {
    return _prefs?.get(key);
  }


  // ------------------- CREATE METHODS (Only Set If Key Doesn't Exist) -------------------

  Future<void> createString(String key, String value) async {
    if (_prefs?.containsKey(key) == true) {
      return;
    }
    await setString(key, value);
  }

  Future<void> createInt(String key, int value) async {
    if (_prefs?.containsKey(key) == true) {
      return;
    }
    await setInt(key, value);
  }

  Future<void> createBool(String key, bool value) async {
    if (_prefs?.containsKey(key) == true) {
      return;
    }
    await setBool(key, value);
  }

  Future<void> createDouble(String key, double value) async {
    if (_prefs?.containsKey(key) == true) {
      return;
    }
    await setDouble(key, value);
  }

  Future<void> createStringList(String key, List<String> value) async {
    if (_prefs?.containsKey(key) == true) {
      return;
    }
    await setStringList(key, value);
  }

  // ------------------- SETTER METHODS (Always Set the Value) -------------------

  Future<void> setString(String key, String value) async {
    await _prefs?.setString(key, value);
  }

  Future<void> setInt(String key, int value) async {
    await _prefs?.setInt(key, value);
  }

  Future<void> setBool(String key, bool value) async {
    await _prefs?.setBool(key, value);
  }

  Future<void> setDouble(String key, double value) async {
    await _prefs?.setDouble(key, value);
  }

  /// ✅ Store list as JSON string safely
  Future<void> setStringList(String key, List<String> value) async {
    await _prefs?.setString(key, jsonEncode(value));
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
      return [];
    }

    try {
      return List<String>.from(jsonDecode(jsonString)); // ✅ Convert JSON back to List<String>
    } catch (e) {
      return []; // ✅ Return an empty list instead of crashing
    }
  }


  // ------------------- UTILITY METHODS -------------------

  Future<void> remove(String key) async {
    await _prefs?.remove(key);
  }

  Future<void> clear() async {
    await _prefs?.clear();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
