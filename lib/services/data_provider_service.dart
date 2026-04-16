import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart' as app_user;
import '../models/task.dart';
import '../services/supabase_service.dart';
import '../services/firebase_service.dart';

enum ProviderType { supabase, firebase }

class DataProviderService {
  static bool _initialized = false;
  static ProviderType? _currentAuthProvider;
  
  // Configuration properties
  static List<ProviderType> _priority = [];
  static List<ProviderType> _activeProviders = [];
  static bool _simultaneousWrites = true;
  
  static const String _priorityKey = 'provider_priority';
  static const String _activeProvidersKey = 'active_providers';
  static const String _simultaneousWritesKey = 'simultaneous_writes';

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Try to load from SharedPreferences first (runtime configuration)
      final savedPriority = prefs.getStringList(_priorityKey);
      final savedActive = prefs.getStringList(_activeProvidersKey);
      final savedSimultaneous = prefs.getBool(_simultaneousWritesKey);

      if (savedPriority != null && savedPriority.isNotEmpty) {
        _priority = savedPriority
            .map((e) => _parseProviderType(e.trim()))
            .where((type) => type != null)
            .cast<ProviderType>()
            .toList();
      } else {
        // Load provider priority from environment
        final priorityString = dotenv.env['PROVIDER_PRIORITY'] ?? 'supabase,firebase';
        _priority = priorityString
            .split(',')
            .map((e) => _parseProviderType(e.trim()))
            .where((type) => type != null)
            .cast<ProviderType>()
            .toList();
      }

      if (savedActive != null && savedActive.isNotEmpty) {
        _activeProviders = savedActive
            .map((e) => _parseProviderType(e.trim()))
            .where((type) => type != null)
            .cast<ProviderType>()
            .toList();
      } else {
        // Load active providers from environment
        final activeString = dotenv.env['ACTIVE_PROVIDERS'] ?? 'supabase,firebase';
        _activeProviders = activeString
            .split(',')
            .map((e) => _parseProviderType(e.trim()))
            .where((type) => type != null)
            .cast<ProviderType>()
            .toList();
      }

      // Load simultaneous writes setting
      if (savedSimultaneous != null) {
        _simultaneousWrites = savedSimultaneous;
      } else {
        _simultaneousWrites = dotenv.env['SIMULTANEOUS_WRITES']?.toLowerCase() == 'true';
      }

      _initialized = true;

      if (kDebugMode) {
        debugPrint('DataProviderService initialized with configuration:');
        debugPrint('Priority: ${_priority.map((e) => e.name)}');
        debugPrint('Active: ${_activeProviders.map((e) => e.name)}');
        debugPrint('Simultaneous Writes: $_simultaneousWrites');
      }
    } catch (e) {
      debugPrint('Error loading provider configuration: $e');
      // Fallback to defaults
      _priority = [ProviderType.supabase, ProviderType.firebase];
      _activeProviders = [ProviderType.supabase, ProviderType.firebase];
      _simultaneousWrites = true;
      _initialized = true;
    }
  }

  static ProviderType? _parseProviderType(String name) {
    switch (name.toLowerCase()) {
      case 'supabase':
        return ProviderType.supabase;
      case 'firebase':
        return ProviderType.firebase;
      default:
        debugPrint('Unknown provider: $name');
        return null;
    }
  }

  
  
  // Get configuration methods
  static List<ProviderType> getProviderPriority() {
    if (!_initialized) {
      debugPrint('DataProviderService not initialized, using defaults');
      return [ProviderType.supabase, ProviderType.firebase];
    }
    return List.from(_priority);
  }

  static List<ProviderType> getActiveProviders() {
    if (!_initialized) {
      debugPrint('DataProviderService not initialized, using defaults');
      return [ProviderType.supabase, ProviderType.firebase];
    }
    return List.from(_activeProviders);
  }

  static bool get simultaneousWrites {
    if (!_initialized) {
      debugPrint('DataProviderService not initialized, using default');
      return true;
    }
    return _simultaneousWrites;
  }

  static bool isProviderActive(ProviderType provider) {
    return getActiveProviders().contains(provider);
  }

  static ProviderType? getPrimaryProvider() {
    final active = getActiveProviders();
    return active.isNotEmpty ? active.first : null;
  }

  static ProviderType? getSecondaryProvider() {
    final active = getActiveProviders();
    return active.length > 1 ? active[1] : null;
  }

  // Runtime configuration methods
  
  /// Change provider priority dynamically
  static Future<bool> setProviderPriority(List<ProviderType> newPriority) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final priorityStrings = newPriority.map((e) => e.name).toList();
      
      await prefs.setStringList(_priorityKey, priorityStrings);
      _priority = List.from(newPriority);
      
      debugPrint('Provider priority updated: ${_priority.map((e) => e.name)}');
      return true;
    } catch (e) {
      debugPrint('Error setting provider priority: $e');
      return false;
    }
  }

  /// Change active providers dynamically
  static Future<bool> setActiveProviders(List<ProviderType> newActiveProviders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeStrings = newActiveProviders.map((e) => e.name).toList();
      
      await prefs.setStringList(_activeProvidersKey, activeStrings);
      _activeProviders = List.from(newActiveProviders);
      
      debugPrint('Active providers updated: ${_activeProviders.map((e) => e.name)}');
      return true;
    } catch (e) {
      debugPrint('Error setting active providers: $e');
      return false;
    }
  }

  /// Switch simultaneous writes setting
  static Future<bool> setSimultaneousWrites(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_simultaneousWritesKey, enabled);
      _simultaneousWrites = enabled;
      
      debugPrint('Simultaneous writes updated: $enabled');
      return true;
    } catch (e) {
      debugPrint('Error setting simultaneous writes: $e');
      return false;
    }
  }

  /// Switch provider order (swap primary and secondary)
  static Future<bool> switchProviderOrder() async {
    if (_priority.length < 2) {
      debugPrint('Not enough providers to switch order');
      return false;
    }

    try {
      final newPriority = <ProviderType>[];
      newPriority.add(_priority[1]); // Secondary becomes primary
      newPriority.add(_priority[0]); // Primary becomes secondary
      
      // Add remaining providers in same order
      for (int i = 2; i < _priority.length; i++) {
        newPriority.add(_priority[i]);
      }
      
      return await setProviderPriority(newPriority);
    } catch (e) {
      debugPrint('Error switching provider order: $e');
      return false;
    }
  }

  /// Get current configuration as a map
  static Map<String, dynamic> getCurrentConfig() {
    return {
      'priority': _priority.map((e) => e.name).toList(),
      'activeProviders': _activeProviders.map((e) => e.name).toList(),
      'simultaneousWrites': _simultaneousWrites,
      'primaryProvider': getPrimaryProvider()?.name,
      'secondaryProvider': getSecondaryProvider()?.name,
    };
  }

  static Future<List<app_user.User>> getUsers() async {
    if (!_initialized) await initialize();

    final priority = getProviderPriority();
    final activeProviders = getActiveProviders();

    debugPrint('Getting users with priority: ${priority.map((e) => e.name)}, active: ${activeProviders.map((e) => e.name)}');

    for (ProviderType providerType in priority) {
      if (!activeProviders.contains(providerType)) continue;

      try {
        final result = await _getUsersFromProvider(providerType);
        debugPrint('Successfully got ${result.length} users from ${providerType.name}');

        // Try to sync to other providers if this succeeds
        _syncToOtherProviders(result, providerType);

        return result;
      } catch (e) {
        debugPrint('Failed to get users from ${providerType.name}: $e');
        continue;
      }
    }

    debugPrint('All providers failed, returning local fallback data');
    return _getLocalFallbackUsers();
  }

  static Future<app_user.User> createUser(app_user.User user) async {
    if (!_initialized) await initialize();

    final activeProviders = getActiveProviders();

    debugPrint('Creating user with simultaneous writes on: ${activeProviders.map((e) => e.name)}');

    if (simultaneousWrites) {
      // SIMULTANEOUS WRITES - Write to all active providers at once
      return await _createUserSimultaneous(user, activeProviders);
    } else {
      // SEQUENTIAL WRITES - Try providers in priority order
      return await _createUserSequential(user);
    }
  }

  static Future<app_user.User> _createUserSimultaneous(app_user.User user, List<ProviderType> activeProviders) async {
    final futures = <Future<app_user.User>>[];

    // Create futures for all active providers
    for (ProviderType providerType in activeProviders) {
      
      futures.add(_createUserInProvider(user, providerType));
    }

    if (futures.isEmpty) {
      debugPrint('No available providers for simultaneous user creation');
      return _getFallbackUser(user);
    }

    try {
      // Wait for all writes to complete
      final results = await Future.wait(futures);

      if (results.isNotEmpty) {
        debugPrint('Successfully created user in ${results.length} providers simultaneously');
        return results.first; // Return first successful result
      }
    } catch (e) {
      debugPrint('Error in simultaneous user creation: $e');
      // Fallback to sequential if simultaneous fails
      return await _createUserSequential(user);
    }

    return _getFallbackUser(user);
  }

  static Future<app_user.User> _createUserSequential(app_user.User user) async {
    final priority = getProviderPriority();
    final activeProviders = getActiveProviders();

    debugPrint('Creating user sequentially with priority: ${priority.map((e) => e.name)}');

    List<app_user.User> createdUsers = [];

    for (ProviderType providerType in priority) {
      if (!activeProviders.contains(providerType)) continue;

      
      try {
        final result = await _createUserInProvider(user, providerType);
        createdUsers.add(result);
        debugPrint('Successfully created user in ${providerType.name}');
      } catch (e) {
        debugPrint('Failed to create user in ${providerType.name}: $e');
        continue;
      }
    }

    if (createdUsers.isNotEmpty) {
      return createdUsers.first; // Return the first successful creation
    }

    debugPrint('All providers failed during user creation');
    return _getFallbackUser(user);
  }

  static Future<app_user.User?> findUser(String identifier) async {
    if (!_initialized) await initialize();

    final priority = getProviderPriority();
    final activeProviders = getActiveProviders();

    for (ProviderType providerType in priority) {
      if (!activeProviders.contains(providerType)) continue;

      
      try {
        final result = await _findUserInProvider(identifier, providerType);
        if (result != null) {
          debugPrint('Found user in ${providerType.name}');
          return result;
        }
      } catch (e) {
        debugPrint('Failed to find user in ${providerType.name}: $e');
        continue;
      }
    }

    debugPrint('User not found in any provider');
    return null;
  }

  static Future<bool> emailExists(String email) async {
    if (!_initialized) await initialize();

    final priority = getProviderPriority();
    final activeProviders = getActiveProviders();

    for (ProviderType providerType in priority) {
      if (!activeProviders.contains(providerType)) continue;

      
      try {
        final result = await _emailExistsInProvider(email, providerType);
        if (result) {
          debugPrint('Email exists in ${providerType.name}');
          return true;
        }
      } catch (e) {
        debugPrint('Failed to check email in ${providerType.name}: $e');
        continue;
      }
    }

    return false;
  }

  // ─── Authentication Methods ────────────────────────────────────────────────────────

  /// Sign up user with email and password across all active providers
  static Future<bool> signUpWithEmail(String email, String password) async {
    if (!_initialized) await initialize();

    final activeProviders = getActiveProviders();
    bool anySuccess = false;

    debugPrint('Signing up user with email across providers: ${activeProviders.map((e) => e.name)}');

    for (ProviderType providerType in activeProviders) {
      
      try {
        await _signUpInProvider(email, password, providerType);
        debugPrint('Successfully signed up user in ${providerType.name}');
        anySuccess = true;
      } catch (e) {
        debugPrint('Failed to sign up user in ${providerType.name}: $e');
        continue;
      }
    }

    return anySuccess;
  }

  /// Sign in user with email and password
  static Future<app_user.User?> signInWithEmail(String email, String password) async {
    if (!_initialized) await initialize();

    final priority = getProviderPriority();
    final activeProviders = getActiveProviders();

    debugPrint('Signing in user with email priority: ${priority.map((e) => e.name)}');

    // Try online authentication first
    for (ProviderType providerType in priority) {
      if (!activeProviders.contains(providerType)) continue;

      
      try {
        await _signInInProvider(email, password, providerType);
        debugPrint('✅ Successfully signed in user with ${providerType.name}');
        _currentAuthProvider = providerType;
        
        // Get user profile after successful authentication
        final user = await _getCurrentUserFromProvider(providerType);
        if (user != null) {
          // Cache credentials for offline use
          await _cacheUserCredentials(email, password, user);
          debugPrint('🔐 Authenticated user: ${user.email} via ${providerType.name}');
          return user;
        }
        
        // Fallback: find user by email
        return await findUser(email);
      } catch (e) {
        debugPrint('❌ Failed to sign in user with ${providerType.name}: $e');
        continue;
      }
    }

    // If all online providers failed, try offline authentication
    debugPrint('All online providers failed, trying offline authentication...');
    return await _signInOffline(email, password);
  }

  /// Sign out user from all providers
  static Future<void> signOut() async {
    if (!_initialized) await initialize();

    final activeProviders = getActiveProviders();

    debugPrint('Signing out from providers: ${activeProviders.map((e) => e.name)}');

    for (ProviderType providerType in activeProviders) {
      try {
        await _signOutInProvider(providerType);
        debugPrint('Successfully signed out from ${providerType.name}');
      } catch (e) {
        debugPrint('Failed to sign out from ${providerType.name}: $e');
        continue;
      }
    }

    // Clear cached credentials on sign out
    await _clearCachedCredentials();
    _currentAuthProvider = null;
  }

  /// Get current authenticated user
  static app_user.User? get currentUser {
    final priority = getProviderPriority();
    final activeProviders = getActiveProviders();

    for (ProviderType providerType in priority) {
      if (!activeProviders.contains(providerType)) continue;

      try {
        final user = _getCurrentUserFromProvider(providerType);
        if (user != null) {
          return user;
        }
      } catch (e) {
        debugPrint('Failed to get current user from ${providerType.name}: $e');
        continue;
      }
    }

    return null;
  }

  //  Task CRUD Operations  _________________________________________________________

  static Future<List<Task>> getTasks({String? userId, bool enableSync = true}) async {
    if (!_initialized) await initialize();

    final priority = getProviderPriority();
    final activeProviders = getActiveProviders();

    debugPrint('Getting tasks with priority: ${priority.map((e) => e.name)}, active: ${activeProviders.map((e) => e.name)}');

    for (ProviderType providerType in priority) {
      if (!activeProviders.contains(providerType)) continue;

      
      try {
        final result = await _getTasksFromProvider(providerType, userId);
        debugPrint('Successfully got ${result.length} tasks from ${providerType.name}');

        // Try to sync to other providers if this succeeds and sync is enabled
        if (enableSync) {
          _syncTasksToOtherProviders(result, providerType);
        }

        return result;
      } catch (e) {
        debugPrint('Failed to get tasks from ${providerType.name}: $e');
        continue;
      }
    }

    debugPrint('All providers failed, returning local fallback tasks');
    return _getLocalFallbackTasks();
  }

  static Future<Task> createTask(Task task) async {
    if (!_initialized) await initialize();

    // Vérifier la connectivité réseau d'abord
    final hasConnectivity = await _hasNetworkConnectivity();
    if (!hasConnectivity) {
      debugPrint('Pas de connectivité réseau, création de tâche hors ligne impossible via DataProvider');
      throw Exception('No network connectivity - use OfflineSyncService for offline operations');
    }

    final activeProviders = getActiveProviders();

    debugPrint('Creating task with simultaneous writes on: ${activeProviders.map((e) => e.name)}');

    if (simultaneousWrites) {
      // SIMULTANEOUS WRITES - Write to all active providers at once
      return await _createTaskSimultaneous(task, activeProviders);
    } else {
      // SEQUENTIAL WRITES - Try providers in priority order
      return await _createTaskSequential(task);
    }
  }

  static Future<bool> _hasNetworkConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      debugPrint('Pas de connectivité réseau: $e');
      return false;
    }
  }

  static Future<Task> _createTaskSimultaneous(Task task, List<ProviderType> activeProviders) async {
    final futures = <Future<Task>>[];

    // Create futures for all active providers
    for (ProviderType providerType in activeProviders) {
      
      futures.add(_createTaskInProvider(task, providerType));
    }

    if (futures.isEmpty) {
      debugPrint('No available providers for simultaneous task creation');
      return _getFallbackTask(task);
    }

    try {
      // Wait for all writes to complete
      final results = await Future.wait(futures);

      if (results.isNotEmpty) {
        debugPrint('Successfully created task in ${results.length} providers simultaneously');
        return results.first; // Return first successful result
      }
    } catch (e) {
      debugPrint('Error in simultaneous task creation: $e');
      // Fallback to sequential if simultaneous fails
      return await _createTaskSequential(task);
    }

    return _getFallbackTask(task);
  }

  static Future<Task> _createTaskSequential(Task task) async {
    final priority = getProviderPriority();
    final activeProviders = getActiveProviders();

    debugPrint('Creating task sequentially with priority: ${priority.map((e) => e.name)}');

    List<Task> createdTasks = [];

    for (ProviderType providerType in priority) {
      if (!activeProviders.contains(providerType)) continue;

      
      try {
        final result = await _createTaskInProvider(task, providerType);
        createdTasks.add(result);
        debugPrint('Successfully created task in ${providerType.name}');
      } catch (e) {
        debugPrint('Failed to create task in ${providerType.name}: $e');
        continue;
      }
    }

    if (createdTasks.isNotEmpty) {
      return createdTasks.first; // Return the first successful creation
    }

    debugPrint('All providers failed during task creation');
    return _getFallbackTask(task);
  }

  static Future<Task> updateTask(Task task) async {
    if (!_initialized) await initialize();

    final activeProviders = getActiveProviders();

    debugPrint('Updating task with simultaneous writes on: ${activeProviders.map((e) => e.name)}');

    if (simultaneousWrites) {
      // SIMULTANEOUS WRITES - Update all active providers at once
      return await _updateTaskSimultaneous(task, activeProviders);
    } else {
      // SEQUENTIAL WRITES - Try providers in priority order
      return await _updateTaskSequential(task);
    }
  }

  static Future<void> deleteTask(String taskId) async {
    if (!_initialized) await initialize();

    final priority = getProviderPriority();
    final activeProviders = getActiveProviders();

    debugPrint('=== DÉBUT SUPPRESSION TÂCHE $taskId ===');
    debugPrint('Priorité: ${priority.map((e) => e.name)}');
    debugPrint('Providers actifs: ${activeProviders.map((e) => e.name)}');

    List<String> successfulDeletes = [];
    List<String> failedDeletes = [];

    for (ProviderType providerType in priority) {
      if (!activeProviders.contains(providerType)) {
        debugPrint('Provider ${providerType.name} n\'est pas actif, skip');
        continue;
      }

      
      try {
        debugPrint('Tentative de suppression depuis ${providerType.name}...');
        await _deleteTaskInProvider(taskId, providerType);
        successfulDeletes.add(providerType.name);
        debugPrint('SUCCESS: Tâche supprimée de ${providerType.name}');
      } catch (e) {
        failedDeletes.add(providerType.name);
        debugPrint('ÉCHEC: Impossible de supprimer de ${providerType.name}: $e');
        debugPrint('Type d\'erreur: ${e.runtimeType}');
        continue;
      }
    }

    debugPrint('=== RÉSULTAT SUPPRESSION ===');
    debugPrint('Succès: ${successfulDeletes.join(", ")}');
    debugPrint('Échecs: ${failedDeletes.join(", ")}');

    if (successfulDeletes.isEmpty) {
      debugPrint('TOUS LES PROVIDERS ONT ÉCHOUÉ - LEVE EXCEPTION');
      throw Exception('Impossible de supprimer la tâche: tous les providers ont échoué');
    } else {
      debugPrint('SUPPRESSION TERMINÉE AVEC SUCCÈS');
    }
  }

  static Future<Task?> findTask(String taskId) async {
    if (!_initialized) await initialize();

    final priority = getProviderPriority();
    final activeProviders = getActiveProviders();

    for (ProviderType providerType in priority) {
      if (!activeProviders.contains(providerType)) continue;

      
      try {
        final result = await _findTaskInProvider(taskId, providerType);
        if (result != null) {
          debugPrint('Found task in ${providerType.name}');
          return result;
        }
      } catch (e) {
        debugPrint('Failed to find task in ${providerType.name}: $e');
        continue;
      }
    }

    debugPrint('Task not found in any provider');
    return null;
  }


  // ─── Private Helper Methods ───────────────────────────────────────────────────


  
  static Future<List<app_user.User>> _getUsersFromProvider(ProviderType provider) async {
    switch (provider) {
      case ProviderType.supabase:
        return await SupabaseService.getUsers();
      case ProviderType.firebase:
        return await FirebaseService.getUsers();
    }
  }

  static Future<app_user.User> _createUserInProvider(app_user.User user, ProviderType provider) async {
    switch (provider) {
      case ProviderType.supabase:
        return await SupabaseService.createUser(user);
      case ProviderType.firebase:
        return await FirebaseService.createUser(user);
    }
  }

  static Future<app_user.User?> _findUserInProvider(String identifier, ProviderType provider) async {
    switch (provider) {
      case ProviderType.supabase:
        return await SupabaseService.findUser(identifier);
      case ProviderType.firebase:
        return await FirebaseService.findUser(identifier);
    }
  }

  static Future<bool> _emailExistsInProvider(String email, ProviderType provider) async {
    switch (provider) {
      case ProviderType.supabase:
        return await SupabaseService.emailExists(email);
      case ProviderType.firebase:
        return await FirebaseService.emailExists(email);
    }
  }

  static Future<void> _signUpInProvider(String email, String password, ProviderType provider) async {
    switch (provider) {
      case ProviderType.supabase:
        await SupabaseService.signUpWithEmail(email, password);
        break;
      case ProviderType.firebase:
        await FirebaseService.signUpWithEmail(email, password);
        break;
    }
  }

  static Future<void> _signInInProvider(String email, String password, ProviderType provider) async {
    switch (provider) {
      case ProviderType.supabase:
        await SupabaseService.signInWithEmail(email, password);
        break;
      case ProviderType.firebase:
        await FirebaseService.signInWithEmail(email, password);
        break;
    }
  }

  static Future<void> _signOutInProvider(ProviderType provider) async {
    switch (provider) {
      case ProviderType.supabase:
        await SupabaseService.signOut();
        break;
      case ProviderType.firebase:
        await FirebaseService.signOut();
        break;
    }
  }

  static app_user.User? _getCurrentUserFromProvider(ProviderType provider) {
    switch (provider) {
      case ProviderType.supabase:
        return SupabaseService.currentUser;
      case ProviderType.firebase:
        return FirebaseService.currentUser;
    }
  }

  static Future<List<Task>> _getTasksFromProvider(ProviderType provider, String? userId) async {
    switch (provider) {
      case ProviderType.supabase:
        return await SupabaseService.getTasks(userId: userId);
      case ProviderType.firebase:
        return await FirebaseService.getTasks(userId: userId);
    }
  }

  static Future<Task> _createTaskInProvider(Task task, ProviderType provider) async {
    switch (provider) {
      case ProviderType.supabase:
        return await SupabaseService.createTask(task);
      case ProviderType.firebase:
        return await FirebaseService.createTask(task);
    }
  }

  static Future<Task> _updateTaskSimultaneous(Task task, List<ProviderType> activeProviders) async {
    final futures = <Future<Task>>[];

    // Create futures for all active providers
    for (ProviderType providerType in activeProviders) {
      
      futures.add(_updateTaskInProvider(task, providerType));
    }

    if (futures.isEmpty) {
      debugPrint('No available providers for simultaneous task update');
      return task;
    }

    try {
      // Wait for all updates to complete
      final results = await Future.wait(futures);

      if (results.isNotEmpty) {
        debugPrint('Successfully updated task in ${results.length} providers simultaneously');
        return results.first; // Return first successful result
      }
    } catch (e) {
      debugPrint('Error in simultaneous task update: $e');
      // Fallback to sequential if simultaneous fails
      return await _updateTaskSequential(task);
    }

    return task;
  }

  static Future<Task> _updateTaskSequential(Task task) async {
    final priority = getProviderPriority();
    final activeProviders = getActiveProviders();

    debugPrint('Updating task sequentially with priority: ${priority.map((e) => e.name)}');

    for (ProviderType providerType in priority) {
      if (!activeProviders.contains(providerType)) continue;

      
      try {
        final result = await _updateTaskInProvider(task, providerType);
        debugPrint('Successfully updated task in ${providerType.name}');
        return result;
      } catch (e) {
        debugPrint('Failed to update task in ${providerType.name}: $e');
        continue;
      }
    }

    debugPrint('All providers failed during task update');
    return task; // Return original task if all fail
  }

  static Future<Task> _updateTaskInProvider(Task task, ProviderType provider) async {
    switch (provider) {
      case ProviderType.supabase:
        return await SupabaseService.updateTask(task);
      case ProviderType.firebase:
        return await FirebaseService.updateTask(task);
    }
  }

  static Future<void> _deleteTaskInProvider(String taskId, ProviderType provider) async {
    switch (provider) {
      case ProviderType.supabase:
        await SupabaseService.deleteTask(taskId);
      case ProviderType.firebase:
        await FirebaseService.deleteTask(taskId);
    }
  }

  static Future<Task?> _findTaskInProvider(String taskId, ProviderType provider) async {
    switch (provider) {
      case ProviderType.supabase:
        return await SupabaseService.findTask(taskId);
      case ProviderType.firebase:
        return await FirebaseService.findTask(taskId);
    }
  }

  static Future<void> _syncTasksToOtherProviders(List<Task> tasks, ProviderType sourceProvider) async {
    final activeProviders = getActiveProviders();

    for (ProviderType targetProvider in activeProviders) {
      if (targetProvider == sourceProvider) continue;
      
      try {
        for (final task in tasks) {
          // Vérifie si la tâche existe déjà avant d'écrire → évite les doublons
          final existing = await _findTaskInProvider(task.id, targetProvider);
          if (existing == null) {
            debugPrint('Syncing task ${task.id} to ${targetProvider.name}');
            await _createTaskInProvider(task, targetProvider);
          } else {
            debugPrint('Task ${task.id} already exists in ${targetProvider.name}, skipping sync');
          }
        }
        debugPrint('Synced ${tasks.length} tasks to ${targetProvider.name}');
      } catch (e) {
        debugPrint('Failed to sync tasks to ${targetProvider.name}: $e');
      }
    }
  }

  static List<Task> _getLocalFallbackTasks() {
    return [];
  }

  static Task _getFallbackTask(Task original) {
    return Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: original.title,
      description: original.description,
      status: original.status,
      createdAt: original.createdAt,
      updatedAt: DateTime.now(),
      dueDate: original.dueDate,
      userId: original.userId,
      priority: original.priority,
      tags: original.tags,
    );
  }

  static Future<void> _syncToOtherProviders(List<app_user.User> users, ProviderType sourceProvider) async {
    final activeProviders = getActiveProviders();
    debugPrint('SYNC USERS: Source=${sourceProvider.name}, Active=${activeProviders.map((p) => p.name).join(', ')}');

    for (ProviderType targetProvider in activeProviders) {
      if (targetProvider == sourceProvider) continue;
      
      try {
        debugPrint('SYNC USERS: Syncing ${users.length} users to ${targetProvider.name}');
        for (final user in users) {
          // Vérifie si l'utilisateur existe déjà avant d'écrire pour éviter les doublons
          final existing = await _findUserInProvider(user.email, targetProvider);
          if (existing == null) {
            debugPrint('SYNC USERS: Creating user ${user.email} in ${targetProvider.name}');
            await _createUserInProvider(user, targetProvider);
          } else {
            debugPrint('SYNC USERS: User ${user.email} already exists in ${targetProvider.name}, skipping sync');
          }
        }
        debugPrint('Synced ${users.length} users to ${targetProvider.name}');
      } catch (e) {
        debugPrint('Failed to sync users to ${targetProvider.name}: $e');
      }
    }
  }

  // Méthode publique pour synchroniser les utilisateurs
  static Future<void> syncUsersToOtherProviders(List<app_user.User> users, ProviderType sourceProvider) async {
    await _syncToOtherProviders(users, sourceProvider);
  }

  static List<app_user.User> _getLocalFallbackUsers() {
    return [
      app_user.User(
        id: 'local-fallback-001',
        fullname: 'Local Fallback User',
        email: 'local@transpox.com',
        phone: '771234567',
        country: 'Sénégal',
        state: 'Dakar',
        address: 'Plateau, Dakar',
      ),
    ];
  }

  static app_user.User _getFallbackUser(app_user.User original) {
    return app_user.User(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      fullname: original.fullname,
      email: original.email,
      phone: original.phone,
      country: original.country,
      state: original.state,
      address: original.address,
    );
  }

  // ─── Offline Authentication Methods ────────────────────────────────────────────────

  /// Cache user credentials for offline authentication
  static Future<void> _cacheUserCredentials(String email, String password, app_user.User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_email', email);
      await prefs.setString('cached_password_hash', password.hashCode.toString());
      await prefs.setString('cached_user_data', user.toJsonString());
      await prefs.setBool('credentials_cached', true);
      debugPrint('📱 User credentials cached for offline use');
    } catch (e) {
      debugPrint('Failed to cache credentials: $e');
    }
  }

  /// Sign in using cached credentials (offline mode)
  static Future<app_user.User?> _signInOffline(String email, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasCredentials = prefs.getBool('credentials_cached') ?? false;
      
      if (!hasCredentials) {
        debugPrint('📴 No cached credentials found for offline login');
        return null;
      }

      final cachedEmail = prefs.getString('cached_email');
      final cachedPasswordHash = prefs.getString('cached_password_hash');
      final cachedUserData = prefs.getString('cached_user_data');

      if (cachedEmail != email || cachedPasswordHash != password.hashCode.toString()) {
        debugPrint('📴 Cached credentials do not match');
        return null;
      }

      if (cachedUserData != null) {
        final user = app_user.User.fromJsonString(cachedUserData);
        _currentAuthProvider = null; // Offline mode
        debugPrint('📱 Offline authentication successful for: ${user.email}');
        return user;
      }
    } catch (e) {
      debugPrint('Offline authentication error: $e');
    }

    return null;
  }

  /// Clear cached credentials (called during sign out)
  static Future<void> _clearCachedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_email');
      await prefs.remove('cached_password_hash');
      await prefs.remove('cached_user_data');
      await prefs.remove('credentials_cached');
      debugPrint(' Cached credentials cleared');
    } catch (e) {
      debugPrint('Failed to clear cached credentials: $e');
    }
  }
}