import '../models/task.dart';
import '../models/user.dart';
import 'data_provider_service.dart';
import 'offline_sync_service.dart';
import 'offline_service.dart';
import 'package:uuid/uuid.dart';

class TaskService {
  static const Duration _networkTimeout = Duration(seconds: 10);
  
  // Create a new task
  static Future<Task> createTask({
    required String title,
    required String description,
    required TaskStatus status,
    required String userId,
    DateTime? dueDate,
    int? priority,
    List<String>? tags,
  }) async {
    final newTask = Task(
      id: const Uuid().v4(),
      title: title,
      description: description,
      status: status,
      createdAt: DateTime.now(),
      dueDate: dueDate,
      userId: userId,
      priority: priority ?? 2,
      tags: tags ?? [],
    );

    try {
      await DataProviderService.createTask(newTask).timeout(_networkTimeout);
      return newTask;
    } catch (e) {
      // If network fails, create offline
      await OfflineSyncService.createTaskOffline(newTask);
      return newTask;
    }
  }

  // Update an existing task
  static Future<Task> updateTask(Task task) async {
    final updatedTask = task.copyWith(
      title: task.title,
      description: task.description,
      status: task.status,
      dueDate: task.dueDate,
      priority: task.priority,
      tags: task.tags,
      updatedAt: DateTime.now(),
    );

    try {
      await DataProviderService.updateTask(updatedTask).timeout(_networkTimeout);
      return updatedTask;
    } catch (e) {
      // If network fails, update offline
      await OfflineSyncService.updateTaskOffline(updatedTask);
      return updatedTask;
    }
  }

  // Delete a task
  static Future<bool> deleteTask(String taskId) async {
    try {
      await DataProviderService.deleteTask(taskId).timeout(_networkTimeout);
      return true;
    } catch (e) {
      // If network fails, delete offline
      await OfflineSyncService.deleteTaskOffline(taskId);
      return true;
    }
  }

  // Get all tasks for a user
  static Future<List<Task>> getTasks(String userId, {bool enableSync = true}) async {
    try {
      return await DataProviderService.getTasks(userId: userId, enableSync: enableSync);
    } catch (e) {
      // If network fails, get offline tasks
      return await OfflineService.getOfflineTasks(userId: userId);
    }
  }

  // Sync pending operations
  static Future<void> syncPendingOperations() async {
    try {
      await OfflineSyncService.forceSync();
    } catch (e) {
      throw Exception('Sync failed: $e');
    }
  }

  // Get pending operations count
  static int get pendingOperationsCount => OfflineSyncService.pendingOperationsCount;

  // Clear offline cache for a user
  static Future<void> clearOfflineCache(String userId) async {
    await OfflineService.clearOfflineTasks(userId: userId);
  }

  // Save tasks to offline cache
  static Future<void> saveToOfflineCache(List<Task> tasks, String userId) async {
    await OfflineService.saveTasks(tasks, userId: userId);
  }

  // Get offline tasks for a user
  static Future<List<Task>> getOfflineTasks(String userId) async {
    return await OfflineService.getOfflineTasks(userId: userId);
  }

  // Validate task data
  static String? validateTaskData({
    required String title,
    required String description,
  }) {
    if (title.trim().isEmpty) {
      return 'Le titre est obligatoire';
    }
    
    if (title.length > 100) {
      return 'Le titre ne peut pas dépasser 100 caractères';
    }
    
    if (description.length > 500) {
      return 'La description ne peut pas dépasser 500 caractères';
    }
    
    return null;
  }

  // Filter tasks
  static List<Task> filterTasks({
    required List<Task> tasks,
    String? searchQuery,
    TaskStatus? statusFilter,
    int? priorityFilter,
  }) {
    return tasks.where((task) {
      // Search filter
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase();
        if (!task.title.toLowerCase().contains(query) &&
            !task.description.toLowerCase().contains(query)) {
          return false;
        }
      }
      
      // Status filter
      if (statusFilter != null && task.status != statusFilter) {
        return false;
      }
      
      // Priority filter
      if (priorityFilter != null && task.priority != priorityFilter) {
        return false;
      }
      
      return true;
    }).toList();
  }

  // Sort tasks
  static List<Task> sortTasks(List<Task> tasks, TaskSortOption sortOption) {
    switch (sortOption) {
      case TaskSortOption.titleAsc:
        return tasks..sort((a, b) => a.title.compareTo(b.title));
      case TaskSortOption.titleDesc:
        return tasks..sort((a, b) => b.title.compareTo(a.title));
      case TaskSortOption.dateAsc:
        return tasks..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case TaskSortOption.dateDesc:
        return tasks..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case TaskSortOption.dueDateAsc:
        return tasks..sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
      case TaskSortOption.dueDateDesc:
        return tasks..sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return b.dueDate!.compareTo(a.dueDate!);
        });
      case TaskSortOption.priorityAsc:
        return tasks..sort((a, b) => a.priority.compareTo(b.priority));
      case TaskSortOption.priorityDesc:
        return tasks..sort((a, b) => b.priority.compareTo(a.priority));
    }
  }
}

enum TaskSortOption {
  titleAsc,
  titleDesc,
  dateAsc,
  dateDesc,
  dueDateAsc,
  dueDateDesc,
  priorityAsc,
  priorityDesc,
}
