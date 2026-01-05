import 'dart:async';
import 'package:flutter/widgets.dart';

/// Feature descriptor defines a pluggable UI feature for a slot
///
/// - [featureId]: unique id within a scope
/// - [slotId]: named region within a screen/layout
/// - [priority]: smaller value renders earlier (top of list)
/// - [builder]: widget builder invoked when rendering in a slot
/// - [onInit]/[onDispose]: lifecycle hooks when registered/unregistered
/// - [metadata]: optional, typed config for the feature
class FeatureDescriptor {
  final String featureId;
  final String slotId;
  final int priority;
  final Widget Function(BuildContext context) builder;
  final void Function(BuildContext context)? onInit;
  final void Function()? onDispose;
  final Map<String, dynamic>? metadata;

  const FeatureDescriptor({
    required this.featureId,
    required this.slotId,
    required this.builder,
    this.priority = 100,
    this.onInit,
    this.onDispose,
    this.metadata,
  });
}

/// Scoped, lightweight feature registry.
///
/// Uses a singleton manager that maintains per-scope registries.
/// Each scope typically corresponds to a route/screen key.
class FeatureRegistryManager {
  FeatureRegistryManager._internal();
  static final FeatureRegistryManager instance = FeatureRegistryManager._internal();

  // scopeKey -> featureId -> FeatureDescriptor
  final Map<String, Map<String, FeatureDescriptor>> _scopedRegistries = {};

  // Broadcast stream to notify listeners/slots to rebuild
  final StreamController<String> _scopeChangeController = StreamController<String>.broadcast();

  /// Stream emitting scope keys that have changed
  Stream<String> get changes => _scopeChangeController.stream;

  /// Register a feature in a scope
  void register({
    required String scopeKey,
    required FeatureDescriptor feature,
    BuildContext? context,
  }) {
    final scope = _scopedRegistries.putIfAbsent(scopeKey, () => {});
    final alreadyExists = scope.containsKey(feature.featureId);

    scope[feature.featureId] = feature;

    // Fire lifecycle only when newly added
    if (!alreadyExists && feature.onInit != null && context != null) {
      try {
        feature.onInit!.call(context);
      } catch (_) {
        // swallow to avoid crashing UI; features should be robust
      }
    }

    _scopeChangeController.add(scopeKey);
  }

  /// Unregister a feature by id
  void unregister({
    required String scopeKey,
    required String featureId,
  }) {
    final scope = _scopedRegistries[scopeKey];
    if (scope == null) return;

    final removed = scope.remove(featureId);
    if (removed != null) {
      try {
        removed.onDispose?.call();
      } catch (_) {}
      _scopeChangeController.add(scopeKey);
    }
  }

  /// Remove all features for a scope
  void clearScope(String scopeKey) {
    final scope = _scopedRegistries.remove(scopeKey);
    if (scope != null) {
      for (final feature in scope.values) {
        try {
          feature.onDispose?.call();
        } catch (_) {}
      }
      _scopeChangeController.add(scopeKey);
    }
  }

  /// Get features for a slot within a scope, sorted by priority then id
  /// Also includes global features from 'global_app_bar' scope
  List<FeatureDescriptor> getFeaturesForSlot({
    required String scopeKey,
    required String slotId,
  }) {
    final List<FeatureDescriptor> allFeatures = [];
    
    // Get features from the specific scope
    final scope = _scopedRegistries[scopeKey];
    if (scope != null && scope.isNotEmpty) {
      final scopeFeatures = scope.values.where((f) => f.slotId == slotId).toList();
      allFeatures.addAll(scopeFeatures);
    }
    
    // Get features from global scope (if not already looking at global scope)
    if (scopeKey != 'global_app_bar') {
      final globalScope = _scopedRegistries['global_app_bar'];
      if (globalScope != null && globalScope.isNotEmpty) {
        final globalFeatures = globalScope.values.where((f) => f.slotId == slotId).toList();
        allFeatures.addAll(globalFeatures);
      }
    }
    
    // Sort by priority then id
    allFeatures.sort((a, b) {
      final p = a.priority.compareTo(b.priority);
      if (p != 0) return p;
      return a.featureId.compareTo(b.featureId);
    });
    
    return allFeatures;
  }

  /// Debug/inspection helper
  Map<String, List<String>> describeScope(String scopeKey) {
    final scope = _scopedRegistries[scopeKey];
    if (scope == null) return {};
    final bySlot = <String, List<String>>{};
    for (final f in scope.values) {
      bySlot.putIfAbsent(f.slotId, () => []).add(f.featureId);
    }
    for (final entry in bySlot.entries) {
      entry.value.sort();
    }
    return bySlot;
  }

  /// Dispose manager (generally not needed app-wide)
  void dispose() {
    for (final scope in _scopedRegistries.keys.toList()) {
      clearScope(scope);
    }
    _scopeChangeController.close();
  }
}


