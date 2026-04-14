import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import '../models/user.dart' as app_user;
import '../models/task.dart';

class OfflineService {
  static Database? _database;
  static const String _dbName = 'transpox_offline.db';
  static const int _dbVersion = 1;

  static Future<void> initialize() async {
    if (_database != null) return;

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _dbName);
    
    _database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    
    debugPrint('Offline database initialized at: $path');
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        fullname TEXT NOT NULL,
        email TEXT NOT NULL,
        phone TEXT,
        country TEXT,
        state TEXT,
        address TEXT,
        synced INTEGER DEFAULT 0,
        created_at INTEGER,
        updated_at INTEGER,
        operation TEXT, -- 'create', 'update', 'delete'
        pending_sync INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER,
        due_date INTEGER,
        user_id TEXT,
        priority INTEGER DEFAULT 2,
        tags TEXT, -- JSON array
        synced INTEGER DEFAULT 0,
        operation TEXT, -- 'create', 'update', 'delete'
        pending_sync INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        data TEXT,
        created_at INTEGER NOT NULL,
        retry_count INTEGER DEFAULT 0,
        last_error TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_users_email ON users(email);
      CREATE INDEX idx_users_phone ON users(phone);
      CREATE INDEX idx_tasks_user_id ON tasks(user_id);
      CREATE INDEX idx_tasks_status ON tasks(status);
      CREATE INDEX idx_sync_queue_table ON sync_queue(table_name);
      CREATE INDEX idx_sync_queue_pending ON sync_queue(table_name, record_id);
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle database upgrades here
  }

  static Database get database {
    if (_database == null) {
      throw Exception('Database not initialized. Call initialize() first.');
    }
    return _database!;
  }

  // ─── User Operations ──────────────────────────────────────────────────────────

  /// Insère un utilisateur et l'ajoute à la file de synchronisation
  static Future<void> insertUser(app_user.User user) async {
    await saveUser(user, synced: false, operation: 'create', pendingSync: true);
    await _addToSyncQueue('users', user.id, 'create', user.toJson());
    debugPrint('User ${user.id} added to offline storage and sync queue');
  }

  /// Sauvegarde un utilisateur localement (sans ajouter à la file de synchro par défaut)
  static Future<void> saveUser(app_user.User user, {
    bool synced = true, 
    String? operation, 
    bool pendingSync = false
  }) async {
    final db = database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.insert(
      'users',
      {
        'id': user.id,
        'fullname': user.fullname,
        'email': user.email.toLowerCase(),
        'phone': user.phone,
        'country': user.country,
        'state': user.state,
        'address': user.address,
        'synced': synced ? 1 : 0,
        'created_at': now,
        'updated_at': now,
        'operation': operation,
        'pending_sync': pendingSync ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateUser(app_user.User user, {bool fromSync = false}) async {
    final db = database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.update(
      'users',
      {
        'fullname': user.fullname,
        'email': user.email.toLowerCase(),
        'phone': user.phone,
        'country': user.country,
        'state': user.state,
        'address': user.address,
        'synced': fromSync ? 1 : 0,
        'updated_at': now,
        'operation': fromSync ? null : 'update',
        'pending_sync': fromSync ? 0 : 1,
      },
      where: 'id = ?',
      whereArgs: [user.id],
    );

    if (!fromSync) {
      await _addToSyncQueue('users', user.id, 'update', user.toJson());
      debugPrint('User ${user.id} updated in offline storage and sync queue');
    }
  }

  static Future<void> deleteUser(String userId) async {
    final db = database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.update(
      'users',
      {
        'synced': 0,
        'updated_at': now,
        'operation': 'delete',
        'pending_sync': 1,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );

    await _addToSyncQueue('users', userId, 'delete', null);
    debugPrint('User $userId marked for deletion in offline storage');
  }

  static Future<List<app_user.User>> getOfflineUsers() async {
    final db = database;
    final List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: "operation IS NULL OR operation != 'delete'",
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) {
      return app_user.User(
        id: maps[i]['id'],
        fullname: maps[i]['fullname'],
        email: maps[i]['email'],
        phone: maps[i]['phone'] ?? '',
        country: maps[i]['country'] ?? '',
        state: maps[i]['state'] ?? '',
        address: maps[i]['address'] ?? '',
      );
    });
  }

  static Future<app_user.User?> findOfflineUser(String identifier) async {
    final db = database;
    
    final List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: '(email = ? OR phone = ?) AND (operation IS NULL OR operation != \'delete\')',
      whereArgs: [identifier.toLowerCase(), identifier],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      final map = maps.first;
      return app_user.User(
        id: map['id'],
        fullname: map['fullname'],
        email: map['email'],
        phone: map['phone'] ?? '',
        country: map['country'] ?? '',
        state: map['state'] ?? '',
        address: map['address'] ?? '',
      );
    }

    return null;
  }

  static Future<bool> offlineEmailExists(String email) async {
    final db = database;
    final result = await db.query(
      'users',
      where: 'email = ? AND (operation IS NULL OR operation != \'delete\')',
      whereArgs: [email.toLowerCase()],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  // ─── Sync Queue Management ───────────────────────────────────────────────────

  static Future<void> _addToSyncQueue(String tableName, String recordId, String operation, Map<String, dynamic>? data) async {
    final db = database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.insert(
      'sync_queue',
      {
        'table_name': tableName,
        'record_id': recordId,
        'operation': operation,
        'data': data != null ? jsonEncode(data) : null,
        'created_at': now,
      },
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    final db = database;
    
    return await db.query(
      'sync_queue',
      where: 'retry_count < 5',
      orderBy: 'created_at ASC',
    );
  }

  static Future<void> markSyncItemComplete(int syncId) async {
    final db = database;
    
    await db.delete(
      'sync_queue',
      where: 'id = ?',
      whereArgs: [syncId],
    );
  }

  static Future<void> markSyncItemFailed(int syncId, String error) async {
    final db = database;
    
    await db.rawUpdate(
      'UPDATE sync_queue SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
      [error, syncId],
    );
  }

  static Future<void> markUserSynced(String userId) async {
    final db = database;
    
    await db.update(
      'users',
      {
        'synced': 1,
        'pending_sync': 0,
        'operation': null,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  // ─── Statistics ─────────────────────────────────────────────────────────────

  static Future<Map<String, int>> getSyncStats() async {
    final db = database;
    
    final totalUsers = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM users WHERE operation IS NULL OR operation != \'delete\'')
    ) ?? 0;
    
    final pendingUsers = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM users WHERE pending_sync = 1')
    ) ?? 0;
    
    final pendingSyncItems = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sync_queue WHERE retry_count < 5')
    ) ?? 0;
    
    return {
      'totalUsers': totalUsers,
      'pendingUsers': pendingUsers,
      'pendingSyncItems': pendingSyncItems,
    };
  }

  // ─── Cleanup ───────────────────────────────────────────────────────────────

  static Future<void> clearSyncQueue() async {
    final db = database;
    await db.delete('sync_queue');
    debugPrint('Sync queue cleared');
  }

  //  Task Operations  ______________________________________________________________

  static Future<void> insertTask(Task task) async {
    await saveTask(task, synced: false, operation: 'create', pendingSync: true);
    await _addToSyncQueue('tasks', task.id, 'create', task.toJson());
    debugPrint('Task ${task.id} added to offline storage and sync queue');
  }

  static Future<void> saveTask(Task task, {
    bool synced = true, 
    String? operation, 
    bool pendingSync = false
  }) async {
    final db = database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.insert(
      'tasks',
      {
        'id': task.id,
        'title': task.title,
        'description': task.description,
        'status': task.status.name,
        'created_at': task.createdAt.millisecondsSinceEpoch,
        'updated_at': now,
        'due_date': task.dueDate?.millisecondsSinceEpoch,
        'user_id': task.userId,
        'priority': task.priority,
        'tags': jsonEncode(task.tags),
        'synced': synced ? 1 : 0,
        'operation': operation,
        'pending_sync': pendingSync ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateTask(Task task, {bool fromSync = false}) async {
    final db = database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.update(
      'tasks',
      {
        'title': task.title,
        'description': task.description,
        'status': task.status.name,
        'updated_at': now,
        'due_date': task.dueDate?.millisecondsSinceEpoch,
        'user_id': task.userId,
        'priority': task.priority,
        'tags': jsonEncode(task.tags),
        'synced': fromSync ? 1 : 0,
        'operation': fromSync ? null : 'update',
        'pending_sync': fromSync ? 0 : 1,
      },
      where: 'id = ?',
      whereArgs: [task.id],
    );

    if (!fromSync) {
      await _addToSyncQueue('tasks', task.id, 'update', task.toJson());
      debugPrint('Task ${task.id} updated in offline storage and sync queue');
    }
  }

  static Future<void> deleteTask(String taskId) async {
    final db = database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await db.update(
      'tasks',
      {
        'synced': 0,
        'updated_at': now,
        'operation': 'delete',
        'pending_sync': 1,
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );

    await _addToSyncQueue('tasks', taskId, 'delete', null);
    debugPrint('Task $taskId marked for deletion in offline storage');
  }

  static Future<List<Task>> getOfflineTasks({String? userId}) async {
    final db = database;
    String whereClause = "(operation IS NULL OR operation != 'delete')";
    List<dynamic> whereArgs = [];

    if (userId != null) {
      whereClause += ' AND user_id = ?';
      whereArgs.add(userId);
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );

    return maps.map((map) {
      return Task(
        id: map['id'],
        title: map['title'],
        description: map['description'] ?? '',
        status: _parseTaskStatus(map['status']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
        updatedAt: map['updated_at'] != null 
            ? DateTime.fromMillisecondsSinceEpoch(map['updated_at']) 
            : null,
        dueDate: map['due_date'] != null 
            ? DateTime.fromMillisecondsSinceEpoch(map['due_date']) 
            : null,
        userId: map['user_id'],
        priority: map['priority'] ?? 2,
        tags: map['tags'] != null 
            ? List<String>.from(jsonDecode(map['tags'])) 
            : [],
      );
    }).toList();
  }

  static Future<Task?> findOfflineTask(String taskId) async {
    final db = database;
    
    final List<Map<String, dynamic>> maps = await db.query(
      'tasks',
      where: "id = ? AND (operation IS NULL OR operation != 'delete')",
      whereArgs: [taskId],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      final map = maps.first;
      return Task(
        id: map['id'],
        title: map['title'],
        description: map['description'] ?? '',
        status: _parseTaskStatus(map['status']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
        updatedAt: map['updated_at'] != null 
            ? DateTime.fromMillisecondsSinceEpoch(map['updated_at']) 
            : null,
        dueDate: map['due_date'] != null 
            ? DateTime.fromMillisecondsSinceEpoch(map['due_date']) 
            : null,
        userId: map['user_id'],
        priority: map['priority'] ?? 2,
        tags: map['tags'] != null 
            ? List<String>.from(jsonDecode(map['tags'])) 
            : [],
      );
    }

    return null;
  }

  static TaskStatus _parseTaskStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return TaskStatus.pending;
      case 'in_progress':
      case 'inprogress':
        return TaskStatus.in_progress;
      case 'completed':
        return TaskStatus.completed;
      case 'cancelled':
        return TaskStatus.cancelled;
      default:
        return TaskStatus.pending;
    }
  }

  static Future<void> markTaskSynced(String taskId) async {
    final db = database;
    
    await db.update(
      'tasks',
      {
        'synced': 1,
        'pending_sync': 0,
        'operation': null,
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  static Future<void> clearAllData() async {
    final db = database;
    await db.delete('users');
    await db.delete('tasks');
    await db.delete('sync_queue');
    debugPrint('All offline data cleared');
  }

  static Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      debugPrint('Offline database closed');
    }
  }
}
