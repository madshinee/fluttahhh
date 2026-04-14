import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/user.dart' as app_user;
import '../models/task.dart';
import '../services/data_provider_service.dart';
import '../services/offline_service.dart';

class SyncService {
  static Timer? _syncTimer;
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  static bool _isSyncing = false;
  static bool _autoSyncEnabled = true;

  static Future<void> initialize() async {
    await OfflineService.initialize();

    // Listen for connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.isNotEmpty && !results.contains(ConnectivityResult.none) && _autoSyncEnabled) {
        debugPrint('Network connectivity restored, starting auto-sync');
        syncPendingData();
      }
    });

    // Start periodic sync every 5 minutes
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_autoSyncEnabled) {
        syncPendingData();
      }
    });

    debugPrint('SyncService initialized');
  }

  static set autoSyncEnabled(bool enabled) {
    _autoSyncEnabled = enabled;
    debugPrint('Auto-sync ${enabled ? "enabled" : "disabled"}');
  }

  static bool get isSyncing => _isSyncing;

  static Future<void> syncPendingData() async {
    if (_isSyncing) {
      debugPrint('Sync already in progress, skipping');
      return;
    }

    final connectivityResults = await Connectivity().checkConnectivity();
    if (connectivityResults.isEmpty || connectivityResults.every((r) => r == ConnectivityResult.none)) {
      debugPrint('No network connectivity, skipping sync');
      return;
    }

    _isSyncing = true;
    debugPrint('Starting data synchronization');

    try {
      final pendingItems = await OfflineService.getPendingSyncItems();

      if (pendingItems.isEmpty) {
        debugPrint('No pending items to sync');
        _isSyncing = false;
        return;
      }

      debugPrint('Found ${pendingItems.length} pending items to sync');

      for (final item in pendingItems) {
        try {
          await _syncItem(item);
          await OfflineService.markSyncItemComplete(item['id']);
          debugPrint('Successfully synced item ${item['id']}');
        } catch (e) {
          debugPrint('Failed to sync item ${item['id']}: $e');
          await OfflineService.markSyncItemFailed(item['id'], e.toString());
        }
      }

      // After syncing, refresh local data with server data
      await _refreshLocalData();

    } catch (e) {
      debugPrint('Sync process failed: $e');
    } finally {
      _isSyncing = false;
      debugPrint('Data synchronization completed');
    }
  }

  static Future<void> _syncItem(Map<String, dynamic> item) async {
    final tableName = item['table_name'] as String;
    final recordId = item['record_id'] as String;
    final operation = item['operation'] as String;
    final data = item['data'] != null ?
    jsonDecode(item['data']) as Map<String, dynamic> : null;

    if (tableName == 'users') {
      await _syncUser(recordId, operation, data);
    } else if (tableName == 'tasks') {
      await _syncTask(recordId, operation, data);
    }
  }

  static Future<void> _syncUser(String recordId, String operation, Map<String, dynamic>? data) async {
    switch (operation) {
      case 'create':
        if (data != null) {
          final user = app_user.User.fromJson(data);
          await DataProviderService.createUser(user);
          await OfflineService.markUserSynced(recordId);
        }
        break;

      case 'update':
        if (data != null) {
          // final user = app_user.User.fromJson(data);
          // await DataProviderService.updateUser(user);
          await OfflineService.markUserSynced(recordId);
        }
        break;

      case 'delete':
      // await DataProviderService.deleteUser(recordId);
        await OfflineService.markUserSynced(recordId);
        break;
    }
  }

  static Future<void> _syncTask(String recordId, String operation, Map<String, dynamic>? data) async {
    switch (operation) {
      case 'create':
        if (data != null) {
          final task = Task.fromJson(data);
          await DataProviderService.createTask(task);
          await OfflineService.markTaskSynced(recordId);
        }
        break;

      case 'update':
        if (data != null) {
          final task = Task.fromJson(data);
          await DataProviderService.updateTask(task);
          await OfflineService.markTaskSynced(recordId);
        }
        break;

      case 'delete':
        await DataProviderService.deleteTask(recordId);
        await OfflineService.markTaskSynced(recordId);
        break;
    }
  }

  static Future<void> _refreshLocalData() async {
    try {
      // Refresh Users
      final serverUsers = await DataProviderService.getUsers();
      final offlineUsers = await OfflineService.getOfflineUsers();

      for (final serverUser in serverUsers) {
        try {
          offlineUsers.firstWhere(
                (user) => user.email == serverUser.email,
          );
          await OfflineService.updateUser(serverUser);
          await OfflineService.markUserSynced(serverUser.id);
        } catch (e) {
          await OfflineService.insertUser(serverUser);
          await OfflineService.markUserSynced(serverUser.id);
        }
      }

      // Refresh Tasks
      final serverTasks = await DataProviderService.getTasks();
      final offlineTasks = await OfflineService.getOfflineTasks();

      for (final serverTask in serverTasks) {
        try {
          offlineTasks.firstWhere((task) => task.id == serverTask.id);
          await OfflineService.updateTask(serverTask);
          await OfflineService.markTaskSynced(serverTask.id);
        } catch (e) {
          await OfflineService.insertTask(serverTask);
          await OfflineService.markTaskSynced(serverTask.id);
        }
      }

      debugPrint('Local data refreshed with server data');
    } catch (e) {
      debugPrint('Failed to refresh local data: $e');
    }
  }

  static Future<Map<String, int>> getSyncStats() async {
    return await OfflineService.getSyncStats();
  }

  static Future<void> forceSyncNow() async {
    await syncPendingData();
  }

  static Future<void> clearSyncQueue() async {
    await OfflineService.clearSyncQueue();
    debugPrint('Sync queue cleared manually');
  }

  static Future<void> dispose() async {
    _syncTimer?.cancel();
    await _connectivitySubscription?.cancel();
    await OfflineService.close();
    debugPrint('SyncService disposed');
  }
}