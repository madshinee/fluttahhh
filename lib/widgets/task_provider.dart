import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/task.dart';
import '../models/user.dart';
import '../services/data_provider_service.dart';
import '../services/offline_sync_service.dart';
import '../services/offline_service.dart';

class TaskProvider with ChangeNotifier {
  List<Task> _tasks = [];
  List<Task> _filteredTasks = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String _searchQuery = '';
  TaskStatus? _filterStatus;
  int? _filterPriority;
  int _pendingOperationsCount = 0;
  bool _isSyncing = false;
  
  final String userId;
  
  TaskProvider({required this.userId}) {
    _initializeListener();
    loadTasks();
  }
  
  // Getters
  List<Task> get tasks => List.unmodifiable(_tasks);
  List<Task> get filteredTasks => List.unmodifiable(_filteredTasks);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String get searchQuery => _searchQuery;
  TaskStatus? get filterStatus => _filterStatus;
  int? get filterPriority => _filterPriority;
  int get pendingOperationsCount => _pendingOperationsCount;
  bool get isSyncing => _isSyncing;
  
  // Initialize listener for pending operations
  void _initializeListener() {
    _pendingOperationsCount = OfflineSyncService.pendingOperationsCount;
    notifyListeners();
  }
  
  // Load tasks
  Future<void> loadTasks() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Always try to get online tasks first
      List<Task> onlineTasks = [];
      List<Task> offlineTasks = [];
      
      try {
        onlineTasks = await DataProviderService.getTasks(userId: userId, enableSync: false);
        await OfflineService.clearOfflineTasks(userId: userId);
        await OfflineService.saveTasks(onlineTasks, userId: userId);
      } catch (e) {
        debugPrint('Failed to load online tasks: $e');
        // If online fails, get cached offline tasks
        offlineTasks = await OfflineService.getOfflineTasks(userId: userId);
      }
      
      // Get offline tasks for any pending operations
      final pendingOfflineTasks = await OfflineService.getOfflineTasks(userId: userId);
      
      // Merge online and offline tasks, with offline tasks taking precedence for same IDs
      final Map<String, Task> mergedTasks = {};
      
      // Add online tasks first
      for (final task in onlineTasks) {
        mergedTasks[task.id] = task;
      }
      
      // Add offline tasks (these will override online tasks with same ID)
      for (final task in pendingOfflineTasks) {
        mergedTasks[task.id] = task;
      }
      
      // If no online tasks, use offline tasks
      if (onlineTasks.isEmpty && offlineTasks.isNotEmpty) {
        for (final task in offlineTasks) {
          mergedTasks[task.id] = task;
        }
      }
      
      _tasks = mergedTasks.values.toList();
      _applyFilters();
      
      // Try to sync pending operations if we have connectivity
      if (_pendingOperationsCount > 0) {
        try {
          await OfflineSyncService.forceSync();
        } catch (syncError) {
          debugPrint('Sync failed, but tasks are loaded: $syncError');
        }
      }
      
    } catch (e) {
      debugPrint('Error loading tasks: $e');
      // Fallback to offline tasks only
      try {
        final offlineTasks = await OfflineService.getOfflineTasks(userId: userId);
        _tasks = offlineTasks;
        _applyFilters();
      } catch (offlineError) {
        debugPrint('Failed to load offline tasks: $offlineError');
        _tasks = [];
        _filteredTasks = [];
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Apply filters and search
  void _applyFilters() {
    _filteredTasks = _tasks.where((task) {
      // Search filter
      if (_searchQuery.isNotEmpty && 
          !task.title.toLowerCase().contains(_searchQuery.toLowerCase()) &&
          !task.description.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      
      // Status filter
      if (_filterStatus != null && task.status != _filterStatus) {
        return false;
      }
      
      // Priority filter
      if (_filterPriority != null && task.priority != _filterPriority) {
        return false;
      }
      
      return true;
    }).toList();
  }
  
  // Update search query
  void updateSearchQuery(String query) {
    _searchQuery = query;
    _applyFilters();
    notifyListeners();
  }
  
  // Update status filter
  void updateStatusFilter(TaskStatus? status) {
    _filterStatus = status;
    _applyFilters();
    notifyListeners();
  }
  
  // Update priority filter
  void updatePriorityFilter(int? priority) {
    _filterPriority = priority;
    _applyFilters();
    notifyListeners();
  }
  
  // Create task
  Future<void> createTask({
    required String title,
    required String description,
    required TaskStatus status,
    DateTime? dueDate,
    int? priority,
  }) async {
    try {
      final newTask = Task(
        id: const Uuid().v4(),
        title: title,
        description: description,
        status: status,
        createdAt: DateTime.now(),
        dueDate: dueDate,
        userId: userId,
        priority: priority ?? 2,
        tags: const [],
      );
      
      // Check connectivity first
      final connectivityResults = await Connectivity().checkConnectivity();
      final isConnected = connectivityResults.any((result) => result != ConnectivityResult.none);
      
      if (!isConnected) {
        debugPrint('No connectivity - creating task offline');
        await OfflineSyncService.createTaskOffline(newTask);
        _tasks.insert(0, newTask);
        _applyFilters();
        notifyListeners();
        return;
      }
      
      // Try online creation
      try {
        await DataProviderService.createTask(newTask);
        await loadTasks();
      } catch (e) {
        debugPrint('Online creation failed, using offline mode: $e');
        await OfflineSyncService.createTaskOffline(newTask);
        _tasks.insert(0, newTask);
        _applyFilters();
        notifyListeners();
      }
    } catch (e, stack) {
      debugPrint('Error creating task: $e');
      rethrow;
    }
  }
  
  // Update task
  Future<void> updateTask(Task task) async {
    try {
      final updatedTask = task.copyWith(
        title: task.title,
        description: task.description,
        status: task.status,
        dueDate: task.dueDate,
        priority: task.priority,
        tags: task.tags,
        updatedAt: DateTime.now(),
      );
      
      // Check connectivity first
      final connectivityResults = await Connectivity().checkConnectivity();
      final isConnected = connectivityResults.any((result) => result != ConnectivityResult.none);
      
      if (!isConnected) {
        debugPrint('No connectivity - updating task offline');
        await OfflineSyncService.updateTaskOffline(updatedTask);
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _tasks[index] = updatedTask;
          _applyFilters();
          notifyListeners();
        }
        return;
      }
      
      // Try online update
      try {
        await DataProviderService.updateTask(updatedTask);
        await loadTasks();
      } catch (e) {
        debugPrint('Online update failed, using offline mode: $e');
        await OfflineSyncService.updateTaskOffline(updatedTask);
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _tasks[index] = updatedTask;
          _applyFilters();
          notifyListeners();
        }
      }
    } catch (e, stack) {
      debugPrint('Error updating task: $e');
      rethrow;
    }
  }
  
  // Delete task
  Future<void> deleteTask(String taskId) async {
    try {
      // Check connectivity first
      final connectivityResults = await Connectivity().checkConnectivity();
      final isConnected = connectivityResults.any((result) => result != ConnectivityResult.none);
      
      if (!isConnected) {
        debugPrint('No connectivity - deleting task offline');
        await OfflineSyncService.deleteTaskOffline(taskId);
        _tasks.removeWhere((t) => t.id == taskId);
        _applyFilters();
        notifyListeners();
        return;
      }
      
      // Try online deletion
      try {
        await DataProviderService.deleteTask(taskId);
        _tasks.removeWhere((t) => t.id == taskId);
        _applyFilters();
        notifyListeners();
      } catch (e) {
        debugPrint('Online deletion failed, using offline mode: $e');
        await OfflineSyncService.deleteTaskOffline(taskId);
        _tasks.removeWhere((t) => t.id == taskId);
        _applyFilters();
        notifyListeners();
      }
    } catch (e, stack) {
      debugPrint('Error deleting task: $e');
      rethrow;
    }
  }
  
  // Force sync
  Future<void> forceSync() async {
    if (_isSyncing) return;
    
    _isSyncing = true;
    notifyListeners();
    
    try {
      await OfflineSyncService.forceSync();
      await loadTasks();
      _pendingOperationsCount = OfflineSyncService.pendingOperationsCount;
      notifyListeners();
    } catch (e) {
      debugPrint('Sync error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }
  
  // Clear all tasks
  Future<void> clearAllTasks() async {
    _tasks.clear();
    _filteredTasks.clear();
    notifyListeners();
  }
}
