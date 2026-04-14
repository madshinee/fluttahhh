import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/task.dart';
import '../models/user.dart' as app_user;
import 'data_provider_service.dart';
import 'error_reporting_service.dart';

enum OfflineOperationType {
  createTask,
  updateTask,
  deleteTask,
  createUser,
  updateUser,
  deleteUser,
}

class OfflineOperation {
  final String id;
  final OfflineOperationType type;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final String? entityId;
  int retryCount;

  OfflineOperation({
    required this.id,
    required this.type,
    required this.data,
    required this.timestamp,
    this.entityId,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString(),
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'entityId': entityId,
      'retryCount': retryCount,
    };
  }

  factory OfflineOperation.fromJson(Map<String, dynamic> json) {
    return OfflineOperation(
      id: json['id'],
      type: OfflineOperationType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => OfflineOperationType.createTask,
      ),
      data: json['data'],
      timestamp: DateTime.parse(json['timestamp']),
      entityId: json['entityId'],
      retryCount: json['retryCount'] ?? 0,
    );
  }
}

class OfflineSyncService {
  static const String _operationsKey = 'offline_operations';
  static const String _lastSyncKey = 'last_sync_timestamp';
  static const int _maxRetryCount = 3;
  static const Duration _syncInterval = Duration(seconds: 30);
  
  static bool _isInitialized = false;
  static bool _isSyncing = false;
  static Timer? _syncTimer;
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static final List<OfflineOperation> _pendingOperations = [];
  static final List<Function(List<OfflineOperation>)> _syncListeners = [];

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _loadPendingOperations();
      _setupConnectivityListener();
      _startPeriodicSync();
      _isInitialized = true;
      
      debugPrint('OfflineSyncService initialized with ${_pendingOperations.length} pending operations');
    } catch (e) {
      debugPrint('Error initializing OfflineSyncService: $e');
      await ErrorReportingService.reportError(e, StackTrace.current, context: {'service': 'OfflineSyncService'});
    }
  }

  /// Ajoute une opération à la file d'attente offline
  static Future<void> addOperation(OfflineOperation operation) async {
    try {
      _pendingOperations.add(operation);
      await _savePendingOperations();
      
      debugPrint('Added offline operation: ${operation.type} for entity: ${operation.entityId}');
      
      // Tenter de synchroniser immédiatement si connecté
      if (await _isConnected()) {
        await _syncPendingOperations();
      }
    } catch (e) {
      debugPrint('Error adding offline operation: $e');
      await ErrorReportingService.reportError(e, StackTrace.current, context: {'operation': operation.type.toString()});
    }
  }

  /// Crée une tâche en mode offline
  static Future<Task> createTaskOffline(Task task) async {
    final operation = OfflineOperation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: OfflineOperationType.createTask,
      data: task.toJson(),
      timestamp: DateTime.now(),
      entityId: task.id,
    );

    await addOperation(operation);
    
    // Retourner la tâche avec un ID temporaire si nécessaire
    if (task.id.isEmpty) {
      return task.copyWith(id: 'offline_${DateTime.now().millisecondsSinceEpoch}');
    }
    
    return task;
  }

  /// Met à jour une tâche en mode offline
  static Future<Task> updateTaskOffline(Task task) async {
    final operation = OfflineOperation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: OfflineOperationType.updateTask,
      data: task.toJson(),
      timestamp: DateTime.now(),
      entityId: task.id,
    );

    await addOperation(operation);
    return task;
  }

  /// Supprime une tâche en mode offline
  static Future<void> deleteTaskOffline(String taskId) async {
    final operation = OfflineOperation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: OfflineOperationType.deleteTask,
      data: {'taskId': taskId},
      timestamp: DateTime.now(),
      entityId: taskId,
    );

    await addOperation(operation);
  }

  /// Crée un utilisateur en mode offline
  static Future<app_user.User> createUserOffline(app_user.User user) async {
    final operation = OfflineOperation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: OfflineOperationType.createUser,
      data: user.toJson(),
      timestamp: DateTime.now(),
      entityId: user.id,
    );

    await addOperation(operation);
    
    if (user.id.isEmpty) {
      return user.copyWith(id: 'offline_${DateTime.now().millisecondsSinceEpoch}');
    }
    
    return user;
  }

  /// Force la synchronisation manuelle
  static Future<SyncResult> forceSync() async {
    if (_isSyncing) {
      return SyncResult(success: false, message: 'Synchronisation déjà en cours');
    }

    try {
      _isSyncing = true;
      debugPrint('Starting manual sync...');
      
      final result = await _syncPendingOperations();
      
      // Notifier les listeners
      for (final listener in _syncListeners) {
        listener(_pendingOperations);
      }
      
      return result;
    } finally {
      _isSyncing = false;
    }
  }

  /// Récupère les opérations en attente
  static List<OfflineOperation> get pendingOperations => List.unmodifiable(_pendingOperations);

  /// Vérifie si des opérations sont en attente
  static bool get hasPendingOperations => _pendingOperations.isNotEmpty;

  /// Récupère le nombre d'opérations en attente
  static int get pendingOperationsCount => _pendingOperations.length;

  /// Ajoute un listener pour les changements de synchronisation
  static void addSyncListener(void Function(List<OfflineOperation>) listener) {
    _syncListeners.add(listener);
  }

  /// Supprime un listener de synchronisation
  static void removeSyncListener(void Function(List<OfflineOperation>) listener) {
    _syncListeners.remove(listener);
  }

  /// Vide toutes les opérations en attente (pour tests)
  static Future<void> clearAllOperations() async {
    _pendingOperations.clear();
    await _savePendingOperations();
    debugPrint('All offline operations cleared');
  }

  /// Simule une panne de provider pendant la synchronisation
  static void simulateProviderFailure(dynamic provider) {
    DataProviderService.forcedFailureProvider = provider;
    DataProviderService.simulateFailure = true;
    debugPrint('Simulating failure for provider: ${provider.name}');
  }

  /// Arrête la simulation de panne
  static void stopFailureSimulation() {
    DataProviderService.simulateFailure = false;
    DataProviderService.forcedFailureProvider = null;
    debugPrint('Stopped failure simulation');
  }

  // Méthodes privées

  static Future<void> _loadPendingOperations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final operationsJson = prefs.getStringList(_operationsKey) ?? [];
      
      _pendingOperations.clear();
      for (final json in operationsJson) {
        final operation = OfflineOperation.fromJson(jsonDecode(json));
        _pendingOperations.add(operation);
      }
      
      debugPrint('Loaded ${_pendingOperations.length} pending operations');
    } catch (e) {
      debugPrint('Error loading pending operations: $e');
    }
  }

  static Future<void> _savePendingOperations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final operationsJson = _pendingOperations.map((op) => jsonEncode(op.toJson())).toList();
      await prefs.setStringList(_operationsKey, operationsJson);
    } catch (e) {
      debugPrint('Error saving pending operations: $e');
    }
  }

  static void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        debugPrint('Network connectivity restored, starting sync...');
        _syncPendingOperations();
      }
    });
  }

  static void _startPeriodicSync() {
    _syncTimer = Timer.periodic(_syncInterval, (timer) async {
      if (await _isConnected() && !_isSyncing) {
        _syncPendingOperations();
      }
    });
  }

  static Future<bool> _isConnected() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (e) {
      debugPrint('Error checking connectivity: $e');
      return false;
    }
  }

  static Future<SyncResult> _syncPendingOperations() async {
    if (_pendingOperations.isEmpty || _isSyncing) {
      return SyncResult(success: true, message: 'No operations to sync');
    }

    _isSyncing = true;
    int successCount = 0;
    int failureCount = 0;
    final List<OfflineOperation> failedOperations = [];

    try {
      debugPrint('Syncing ${_pendingOperations.length} operations...');

      // Trier par timestamp pour respecter l'ordre chronologique
      _pendingOperations.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      for (final operation in _pendingOperations) {
        try {
          final success = await _executeOperation(operation);
          if (success) {
            successCount++;
            debugPrint('Successfully synced operation: ${operation.type}');
          } else {
            failureCount++;
            failedOperations.add(operation);
          }
        } catch (e) {
          failureCount++;
          failedOperations.add(operation);
          debugPrint('Failed to sync operation ${operation.type}: $e');
        }
      }

      // Mettre à jour la liste des opérations en attente
      _pendingOperations.clear();
      _pendingOperations.addAll(failedOperations);
      await _savePendingOperations();

      // Marquer le timestamp de dernière synchronisation
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());

      final message = 'Sync completed: $successCount success, $failureCount failed';
      debugPrint(message);

      return SyncResult(success: failureCount == 0, message: message);
    } finally {
      _isSyncing = false;
    }
  }

  static Future<bool> _executeOperation(OfflineOperation operation) async {
    try {
      switch (operation.type) {
        case OfflineOperationType.createTask:
          final task = Task.fromJson(operation.data);
          await DataProviderService.createTask(task);
          return true;

        case OfflineOperationType.updateTask:
          final task = Task.fromJson(operation.data);
          await DataProviderService.updateTask(task);
          return true;

        case OfflineOperationType.deleteTask:
          final taskId = operation.data['taskId'] as String;
          await DataProviderService.deleteTask(taskId);
          return true;

        case OfflineOperationType.createUser:
          final user = app_user.User.fromJson(operation.data);
          await DataProviderService.createUser(user);
          return true;

        case OfflineOperationType.updateUser:
          // final user = app_user.User.fromJson(operation.data);
          // Implémenter updateUser si nécessaire
          return true;

        case OfflineOperationType.deleteUser:
          // Implémenter deleteUser si nécessaire
          return true;
      }
    } catch (e) {
      debugPrint('Error executing operation ${operation.type}: $e');
      
      // Incrémenter le compteur de retry
      operation.retryCount++;
      
      // Si trop de retries, abandonner l'opération
      if (operation.retryCount >= _maxRetryCount) {
        debugPrint('Max retries reached for operation ${operation.type}, abandoning');
        return true; // Retourner true pour supprimer de la liste
      }
      
      return false;
    }
  }

  static void dispose() {
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
    _syncListeners.clear();
    _isInitialized = false;
  }
}

class SyncResult {
  final bool success;
  final String message;
  final DateTime timestamp;

  SyncResult({
    required this.success,
    required this.message,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return 'SyncResult(success: $success, message: $message, timestamp: $timestamp)';
  }
}
