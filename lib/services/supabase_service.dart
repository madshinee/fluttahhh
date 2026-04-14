import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart' as app_user;
import '../models/task.dart';

class SupabaseService {
  static SupabaseClient? _client;
  
  static SupabaseClient get client {
    _client ??= Supabase.instance.client;
    return _client!;
  }

  // ─── Initialization ────────────────────────────────────────────────────────
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL'] ?? 'https://placeholder.supabase.co',
      anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? 'placeholder-key',
    );
  }


  /// Récupère tous les utilisateurs depuis Supabase
  static Future<List<app_user.User>> getUsers() async {
    try {
      final response = await client
          .from('users')
          .select('*')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 10)); // Timeout de 10 secondes
      
      return List<app_user.User>.from(response.map((json) => app_user.User.fromSupabaseJson(json)));
    } catch (e) {
      debugPrint('Erreur Supabase users: $e');
      return _localUsers();
    }
  }

  /// Crée un nouvel utilisateur dans Supabase (méthode manuelle - utiliser avec précaution)
  /// Note : Le trigger handle_new_user() crée automatiquement les profils lors de l'inscription
  static Future<app_user.User> createUser(app_user.User user) async {
    try {
      final userData = user.toSupabaseJson();
      
      final response = await client
          .from('users')
          .insert(userData)
          .select()
          .single()
          .timeout(const Duration(seconds: 10)); // Timeout de 10 secondes
      
      return app_user.User.fromSupabaseJson(response);
    } catch (e) {
      debugPrint('Erreur création utilisateur manuel: $e');
      // Retourne l'utilisateur avec un ID temporaire en cas d'erreur
      return app_user.User(
        id: DateTime.now().millisecondsSinceEpoch.toString(), // ID temporaire en String
        fullname: user.fullname,
        email: user.email,
        phone: user.phone,
        country: user.country,
        state: user.state,
        address: user.address,
      );
    }
  }

  /// Trouve un utilisateur par email ou téléphone
  static Future<app_user.User?> findUser(String identifier) async {
    try {
      final response = await client
          .from('users')
          .select('*')
          .or('email.eq.$identifier,phone.ilike.%$identifier%')
          .maybeSingle()
          .timeout(const Duration(seconds: 10)); // Timeout de 10 secondes
      
      if (response != null) {
        return app_user.User.fromSupabaseJson(response);
      }
      return null;
    } catch (e) {
      debugPrint('Erreur recherche utilisateur: $e');
      return null;
    }
  }

  /// Vérifie si un email existe dans la base de données
  static Future<bool> emailExists(String email) async {
    try {
      final response = await client
          .from('users')
          .select('id')
          .eq('email', email.toLowerCase())
          .maybeSingle()
          .timeout(const Duration(seconds: 10)); // Timeout de 10 secondes
      
      return response != null;
    } catch (e) {
      debugPrint('Erreur vérification email: $e');
      return false;
    }
  }

  /// Authentification avec email et mot de passe
  static Future<AuthResponse> signInWithEmail(String email, String password) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Inscription avec email et mot de passe
  static Future<AuthResponse> signUpWithEmail(String email, String password, {Map<String, String>? data}) async {
    return await client.auth.signUp(
      email: email,
      password: password,
      data: data ?? {},
      emailRedirectTo: 'http://192.168.1.11:8080',
    );
  }

  /// Réinitialisation du mot de passe - envoie un email de réinitialisation
  static Future<void> resetPassword(String email) async {
    await client.auth.resetPasswordForEmail(email);
  }

/// Met à jour le mot de passe de l'utilisateur (après réinitialisation)
  static Future<void> updatePassword(String newPassword) async {
    await client.auth.updateUser(UserAttributes(
      password: newPassword,
    ));
  }

  /// Authentification par téléphone avec OTP
  static Future<void> signInWithPhone(String phone) async {
    await client.auth.signInWithOtp(
      phone: phone,
    );
  }

  /// Vérification du code OTP
  static Future<AuthResponse> verifyOTP(String phone, String token) async {
    return await client.auth.verifyOTP(
      phone: phone,
      token: token,
      type: OtpType.sms,
    );
  }

  /// Déconnexion
  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  /// Récupérer l'utilisateur courant
  static app_user.User? get currentUser {
    final session = client.auth.currentSession;
    if (session?.user != null) {
      return app_user.User.fromSupabaseUser(session!.user);
    }
    return null;
  }

  
  // ════════════════════════════════════════════════════════════════════════════
  //  Données locales de secours (fallback)
  // ════════════════════════════════════════════════════════════════════════════

  static List<app_user.User> _localUsers() {
    return [
      app_user.User(
        id: '123e4567-e89b-12d3-a456-426614174001', // UUID exemple
        fullname: 'Utilisateur Test',
        email: 'test@transpox.com', phone: '771234567',
        country: 'Sénégal', state: 'Dakar', address: 'Plateau, Dakar',
      ),
      app_user.User(
        id: '123e4567-e89b-12d3-a456-426614174002', // UUID exemple
        fullname: 'Demo User',
        email: 'demo@transpox.com', phone: '777654321',
        country: 'France', state: 'Paris', address: 'Champs-Élysées, Paris',
      ),
    ];
  }

  //  Task Management  ______________________________________________________________

  /// Récupère toutes les tâches depuis Supabase
  static Future<List<Task>> getTasks({String? userId}) async {
    try {
      var query = client.from('tasks').select('*');
      
      if (userId != null) {
        query = query.eq('user_id', userId);
      }
      
      final response = await query.order('created_at', ascending: false);
      
      return List<Task>.from(response.map((json) => Task.fromSupabaseJson(json)));
    } catch (e) {
      debugPrint('Erreur Supabase tasks: $e');
      return _localTasks();
    }
  }

  /// Crée une nouvelle tâche dans Supabase
  static Future<Task> createTask(Task task) async {
    try {
      final taskData = task.toSupabaseJson();
      debugPrint('Tentative création tâche Supabase avec données: $taskData');
      
      final response = await client
          .from('tasks')
          .insert(taskData)
          .select()
          .single();
      
      debugPrint('Tâche créée avec succès dans Supabase: $response');
      return Task.fromSupabaseJson(response);
    } catch (e) {
      debugPrint('ERREUR CRÉATION TÂCHE SUPABASE: $e');
      debugPrint('Type d\'erreur: ${e.runtimeType}');
      
      // Renvoyer l'erreur pour permettre une meilleure gestion
      rethrow;
    }
  }

  /// Met à jour une tâche existante dans Supabase
  static Future<Task> updateTask(Task task) async {
    try {
      final taskData = task.toSupabaseJson();
      
      final response = await client
          .from('tasks')
          .update(taskData)
          .eq('id', task.id)
          .select()
          .single();
      
      return Task.fromSupabaseJson(response);
    } catch (e) {
      debugPrint('Erreur mise à jour tâche Supabase: $e');
      return task;
    }
  }

  /// Supprime une tâche dans Supabase
  static Future<void> deleteTask(String taskId) async {
    try {
      await client.from('tasks').delete().eq('id', taskId);
    } catch (e) {
      debugPrint('Erreur suppression tâche Supabase: $e');
      throw Exception('Impossible de supprimer la tâche: $e');
    }
  }

  /// Trouve une tâche par son ID
  static Future<Task?> findTask(String taskId) async {
    try {
      final response = await client
          .from('tasks')
          .select('*')
          .eq('id', taskId)
          .maybeSingle();
      
      if (response != null) {
        return Task.fromSupabaseJson(response);
      }
      return null;
    } catch (e) {
      debugPrint('Erreur recherche tâche Supabase: $e');
      return null;
    }
  }

  static List<Task> _localTasks() {
    return [];
  }
}
