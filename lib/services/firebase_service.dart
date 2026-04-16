import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' show FirebaseStorage, Reference, SettableMetadata, FullMetadata;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/user.dart' as app_user;
import '../models/task.dart';

class FirebaseService {
  static FirebaseApp? _app;
  static FirebaseFirestore? _firestore;
  static FirebaseAuth? _auth;
  static FirebaseStorage? _storage;
  
  // Real-time listeners
  static final Map<String, StreamSubscription> _listeners = {};

  static Future<void> initialize() async {
    try {
      // Configuration Firebase depuis .env (recommandé pour la sécurité)
      final projectId = dotenv.env['FIREBASE_PROJECT_ID'];
      final apiKey = dotenv.env['FIREBASE_API_KEY'];
      final appId = dotenv.env['FIREBASE_APP_ID'];
      final messagingSenderId = dotenv.env['FIREBASE_MESSAGING_SENDER_ID'];
      final storageBucket = dotenv.env['FIREBASE_STORAGE_BUCKET'];
      final authDomain = dotenv.env['FIREBASE_AUTH_DOMAIN'];

      if (projectId == null || projectId.isEmpty ||
          apiKey == null || apiKey.isEmpty ||
          appId == null || appId.isEmpty ||
          messagingSenderId == null || messagingSenderId.isEmpty) {
        throw Exception(
          'Firebase configuration incomplète. Vérifie dans .env :\n'
              'FIREBASE_PROJECT_ID, FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_MESSAGING_SENDER_ID',
        );
      }

      // Éviter double initialisation
      if (Firebase.apps.isNotEmpty) {
        _app = Firebase.apps.first;
        debugPrint('Firebase app already exists, using existing instance');
      } else {
        try {
          _app = await Firebase.initializeApp(
            options: FirebaseOptions(
              apiKey: apiKey,
              appId: appId,
              messagingSenderId: messagingSenderId,
              projectId: projectId,
              storageBucket: storageBucket,
              authDomain: authDomain,
            ),
          );
        } catch (e) {
          if (e.toString().contains('duplicate-app')) {
            _app = Firebase.apps.first;
            debugPrint('Firebase duplicate app detected, using existing instance');
          } else {
            rethrow;
          }
        }
      }

      _firestore = FirebaseFirestore.instance;
      _auth = FirebaseAuth.instance;
      _storage = FirebaseStorage.instance;

      _firestore!.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      debugPrint('Firebase initialisé avec succès (project: $projectId)');
    } catch (e) {
      debugPrint('Firebase initialization error: $e');
      rethrow;
    }
  }

  static FirebaseFirestore get firestore {
    if (_firestore == null) {
      throw Exception('FirebaseService not initialized. Call initialize() first.');
    }
    return _firestore!;
  }

  static FirebaseAuth get auth {
    if (_auth == null) {
      throw Exception('FirebaseService not initialized. Call initialize() first.');
    }
    return _auth!;
  }

  static FirebaseStorage get storage {
    if (_storage == null) {
      throw Exception('FirebaseService not initialized. Call initialize() first.');
    }
    return _storage!;
  }

  // ─── User Management ────────────────────────────────────────────────────────

  static Future<List<app_user.User>> getUsers() async {
    try {
      final snapshot = await firestore
          .collection('users')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => app_user.User.fromFirebaseJson(doc.id, doc.data()))
          .toList();
    } catch (e) {
      debugPrint('Firebase users error: $e');
      return _localUsers();
    }
  }

  static Future<app_user.User> createUser(app_user.User user) async {
    try {
      final userData = user.toFirebaseJson();

      final docRef = await firestore.collection('users').add(userData);
      final createdUser = await docRef.get();

      return app_user.User.fromFirebaseJson(createdUser.id, createdUser.data()!);
    } catch (e) {
      debugPrint('Firebase create user error: $e');
      return app_user.User(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        fullname: user.fullname,
        email: user.email,
        phone: user.phone,
        country: user.country,
        state: user.state,
        address: user.address,
      );
    }
  }

  static Future<app_user.User?> findUser(String identifier) async {
    try {
      final emailQuery = await firestore
          .collection('users')
          .where('email', isEqualTo: identifier.toLowerCase())
          .limit(1)
          .get();

      if (emailQuery.docs.isNotEmpty) {
        final doc = emailQuery.docs.first;
        return app_user.User.fromFirebaseJson(doc.id, doc.data());
      }

      final phoneQuery = await firestore
          .collection('users')
          .where('phone', isEqualTo: identifier)
          .limit(1)
          .get();

      if (phoneQuery.docs.isNotEmpty) {
        final doc = phoneQuery.docs.first;
        return app_user.User.fromFirebaseJson(doc.id, doc.data());
      }

      return null;
    } catch (e) {
      debugPrint('Firebase find user error: $e');
      return null;
    }
  }

  static Future<bool> emailExists(String email) async {
    try {
      final snapshot = await firestore
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase())
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Firebase email exists error: $e');
      return false;
    }
  }

  // ─── Authentication ──────────────────────────────────────────────────────────

  static Future<UserCredential> signInWithEmail(String email, String password) async {
    return await auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  static Future<UserCredential> signUpWithEmail(String email, String password) async {
    return await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> resetPassword(String email) async {
    await auth.sendPasswordResetEmail(email: email);
  }

  static Future<void> updatePassword(String newPassword) async {
    await auth.currentUser?.updatePassword(newPassword);
  }

  static Future<void> signOut() async {
    await auth.signOut();
  }

  static app_user.User? get currentUser {
    final user = auth.currentUser;
    if (user != null) {
      return app_user.User.fromFirebaseUser(user);
    }
    return null;
  }


  // ─── Local Fallback Data ─────────────────────────────────────────────────────

  static List<app_user.User> _localUsers() {
    return [
      app_user.User(
        id: 'firebase-001',
        fullname: 'Firebase Test User',
        email: 'firebase@transpox.com',
        phone: '771234567',
        country: 'Sénégal',
        state: 'Dakar',
        address: 'Plateau, Dakar',
      ),
      app_user.User(
        id: 'firebase-002',
        fullname: 'Firebase Demo User',
        email: 'demo@transpox.com',
        phone: '777654321',
        country: 'France',
        state: 'Paris',
        address: 'Champs-Élysées, Paris',
      ),
    ];
  }

  //  Task Management  ______________________________________________________________

  /// Récupère toutes les tâches depuis Firebase
  static Future<List<Task>> getTasks({String? userId}) async {
    try {
      Query<Map<String, dynamic>> query = firestore.collection('tasks');

      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }

      final snapshot = await query.orderBy('createdAt', descending: true).get();

      return snapshot.docs
          .map((doc) => Task.fromFirebaseJson(doc.id, doc.data()))
          .toList();
    } catch (e) {
      debugPrint('Firebase tasks error: $e');
      return _localTasks();
    }
  }

  /// Crée une nouvelle tâche dans Firebase
  static Future<Task> createTask(Task task) async {
    try {
      final taskData = task.toFirebaseJson();

      final docRef = await firestore.collection('tasks').add(taskData);
      final createdTask = await docRef.get();

      return Task.fromFirebaseJson(createdTask.id, createdTask.data()!);
    } catch (e) {
      debugPrint('Firebase create task error: $e');
      return task.copyWith(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
      );
    }
  }

  /// Met à jour une tâche existante dans Firebase
  static Future<Task> updateTask(Task task) async {
    try {
      final taskData = task.toFirebaseJson();
      String firebaseDocId = '';
      bool taskFound = false;
      
      // 1. Chercher d'abord directement avec l'ID (méthode principale)
      try {
        final doc = await firestore.collection('tasks').doc(task.id).get();
        if (doc.exists) {
          firebaseDocId = task.id;
          taskFound = true;
          debugPrint('Firebase: Tâche trouvée directement pour mise à jour avec ID: $firebaseDocId');
        }
      } catch (e) {
        debugPrint('Firebase: Erreur recherche directe pour mise à jour: $e');
      }
      
      // 2. Si non trouvé, chercher via supabaseId (cas synchronisation)
      if (!taskFound) {
        try {
          final query = await firestore
              .collection('tasks')
              .where('supabaseId', isEqualTo: task.id)
              .limit(1)
              .get();
          
          if (query.docs.isNotEmpty) {
            firebaseDocId = query.docs.first.id;
            taskFound = true;
            debugPrint('Firebase: Tâche trouvée via supabaseId pour mise à jour, ID Firebase: $firebaseDocId');
          }
        } catch (e) {
          debugPrint('Firebase: Erreur recherche via supabaseId pour mise à jour: $e');
        }
      }
      
      // 3. Si toujours non trouvé, créer le document
      if (!taskFound) {
        debugPrint('Firebase: Tâche ${task.id} introuvable pour mise à jour - création du document');
        final docRef = await firestore.collection('tasks').add(taskData);
        firebaseDocId = docRef.id;
      }
      
      // 4. Mettre à jour le document trouvé/créé
      debugPrint('Firebase: Mise à jour du document $firebaseDocId...');
      await firestore.collection('tasks').doc(firebaseDocId).update(taskData);
      
      final updatedDoc = await firestore.collection('tasks').doc(firebaseDocId).get();
      debugPrint('Firebase: Tâche $firebaseDocId mise à jour avec succès');
      return Task.fromFirebaseJson(updatedDoc.id, updatedDoc.data()!);
      
    } catch (e) {
      debugPrint('Firebase update task error: $e');
      debugPrint('Type d\'erreur: ${e.runtimeType}');
      return task;
    }
  }

  /// Supprime une tâche dans Firebase
  static Future<void> deleteTask(String taskId) async {
    try {
      debugPrint('Firebase: Début suppression de la tâche $taskId');
      
      String firebaseDocId = '';
      bool taskFound = false;
      
      // 1. Chercher d'abord via supabaseId (méthode moderne)
      try {
        final query = await firestore
            .collection('tasks')
            .where('supabaseId', isEqualTo: taskId)
            .limit(1)
            .get();
        
        if (query.docs.isNotEmpty) {
          firebaseDocId = query.docs.first.id;
          taskFound = true;
          debugPrint('Firebase: Tâche trouvée via supabaseId, ID Firebase: $firebaseDocId');
        }
      } catch (e) {
        debugPrint('Firebase: Erreur recherche via supabaseId: $e');
      }
      
      // 2. Si non trouvé, essayer directement avec l'ID (cas compatibilité)
      if (!taskFound) {
        try {
          final doc = await firestore.collection('tasks').doc(taskId).get();
          if (doc.exists) {
            firebaseDocId = taskId;
            taskFound = true;
            debugPrint('Firebase: Tâche trouvée directement avec ID: $firebaseDocId');
          }
        } catch (e) {
          debugPrint('Firebase: Erreur recherche directe: $e');
        }
      }
      
      // 3. Si toujours non trouvé, ignorer silencieusement
      if (!taskFound) {
        debugPrint('Firebase: Tâche $taskId introuvable - suppression ignorée (normal si seule dans Supabase)');
        return;
      }
      
      // 4. Supprimer le document trouvé
      debugPrint('Firebase: Suppression du document $firebaseDocId...');
      await firestore.collection('tasks').doc(firebaseDocId).delete();
      debugPrint('Firebase: Tâche $firebaseDocId supprimée avec succès');
      
    } catch (e) {
      debugPrint('Firebase: Erreur critique suppression: $e');
      debugPrint('Type d\'erreur: ${e.runtimeType}');
      
      // Ne pas lever d'exception pour éviter de casser le flux de suppression
      debugPrint('Firebase: Suppression Firebase échouée mais flux maintenu');
    }
  }

  /// Trouve une tâche par son ID
  static Future<Task?> findTask(String taskId) async {
    try {
      final doc = await firestore.collection('tasks').doc(taskId).get();

      if (doc.exists) {
        return Task.fromFirebaseJson(doc.id, doc.data()!);
      }
      return null;
    } catch (e) {
      debugPrint('Firebase find task error: $e');
      return null;
    }
  }

  static List<Task> _localTasks() {
    return [];
  }

  // ─── Real-time Listeners ─────────────────────────────────────────────────────

  /// Écoute les changements en temps réel sur la collection des tâches
  static Stream<List<Task>> watchTasks({String? userId}) {
    Query<Map<String, dynamic>> query = firestore.collection('tasks');
    
    if (userId != null) {
      query = query.where('userId', isEqualTo: userId);
    }

    return query
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Task.fromFirebaseJson(doc.id, doc.data()))
            .toList())
        .handleError((error) {
      debugPrint('Real-time tasks error: $error');
      return _localTasks();
    });
  }

  /// Écoute les changements en temps réel sur la collection des utilisateurs
  static Stream<List<app_user.User>> watchUsers() {
    return firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => app_user.User.fromFirebaseJson(doc.id, doc.data()))
            .toList())
        .handleError((error) {
      debugPrint('Real-time users error: $error');
      return _localUsers();
    });
  }

  /// Écoute les changements sur un document spécifique
  static Stream<DocumentSnapshot> watchDocument(String collection, String documentId) {
    return firestore.collection(collection).doc(documentId).snapshots();
  }

  /// Ajoute un listener personnalisé et retourne son ID
  static String addCustomListener(String listenerId, StreamSubscription subscription) {
    _listeners[listenerId] = subscription;
    return listenerId;
  }

  /// Arrête un listener spécifique
  static void stopListener(String listenerId) {
    _listeners[listenerId]?.cancel();
    _listeners.remove(listenerId);
  }

  /// Arrête tous les listeners actifs
  static void stopAllListeners() {
    for (final subscription in _listeners.values) {
      subscription.cancel();
    }
    _listeners.clear();
  }

  // ─── Firebase Storage ───────────────────────────────────────────────────────

  /// Upload un fichier vers Firebase Storage
  static Future<String> uploadFile(
    String filePath,
    String fileName, {
    String? folder,
    Map<String, String>? metadata,
  }) async {
    try {
      final ref = folder != null 
          ? storage.ref().child(folder).child(fileName)
          : storage.ref().child(fileName);

      final uploadTask = await ref.putFile(
        filePath as dynamic, // Cast to dynamic for File type
        metadata != null ? SettableMetadata(customMetadata: metadata) : null,
      );

      final downloadUrl = await uploadTask.ref.getDownloadURL();
      debugPrint('File uploaded successfully: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('File upload error: $e');
      rethrow;
    }
  }

  /// Upload depuis des bytes (pour les images en mémoire)
  static Future<String> uploadBytes(
    Uint8List bytes,
    String fileName, {
    String? folder,
    Map<String, String>? metadata,
  }) async {
    try {
      final ref = folder != null 
          ? storage.ref().child(folder).child(fileName)
          : storage.ref().child(fileName);

      final uploadTask = await ref.putData(
        bytes,
        metadata != null ? SettableMetadata(customMetadata: metadata) : null,
      );

      final downloadUrl = await uploadTask.ref.getDownloadURL();
      debugPrint('Bytes uploaded successfully: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('Bytes upload error: $e');
      rethrow;
    }
  }

  /// Supprime un fichier de Firebase Storage
  static Future<void> deleteFile(String fileUrl) async {
    try {
      final ref = storage.refFromURL(fileUrl);
      await ref.delete();
      debugPrint('File deleted successfully: $fileUrl');
    } catch (e) {
      debugPrint('File deletion error: $e');
      rethrow;
    }
  }

  /// Récupère les métadonnées d'un fichier
  static Future<FullMetadata> getFileMetadata(String fileUrl) async {
    try {
      final ref = storage.refFromURL(fileUrl);
      return await ref.getMetadata();
    } catch (e) {
      debugPrint('Get file metadata error: $e');
      rethrow;
    }
  }

  // ─── Advanced Firestore Operations ───────────────────────────────────────────

  /// Requête avec pagination
  static Future<List<Task>> getTasksPaginated({
    String? userId,
    DocumentSnapshot? startAfter,
    int limit = 20,
  }) async {
    try {
      Query<Map<String, dynamic>> query = firestore
          .collection('tasks')
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => Task.fromFirebaseJson(doc.id, doc.data()))
          .toList();
    } catch (e) {
      debugPrint('Paginated tasks error: $e');
      return [];
    }
  }

  /// Recherche全文 dans les tâches
  static Future<List<Task>> searchTasks(String searchTerm, {String? userId}) async {
    try {
      Query<Map<String, dynamic>> query = firestore
          .collection('tasks')
          .orderBy('createdAt', descending: true);

      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }

      final snapshot = await query.get();
      
      return snapshot.docs
          .map((doc) => Task.fromFirebaseJson(doc.id, doc.data()))
          .where((task) => 
              task.title.toLowerCase().contains(searchTerm.toLowerCase()) ||
              task.description.toLowerCase().contains(searchTerm.toLowerCase()))
          .toList();
    } catch (e) {
      debugPrint('Search tasks error: $e');
      return [];
    }
  }

  /// Transaction pour mettre à jour plusieurs documents atomiquement
  static Future<void> updateTasksInTransaction(List<Task> tasks) async {
    try {
      await firestore.runTransaction((transaction) async {
        for (final task in tasks) {
          final docRef = firestore.collection('tasks').doc(task.id);
          transaction.update(docRef, task.toFirebaseJson());
        }
      });
      debugPrint('Transaction completed successfully');
    } catch (e) {
      debugPrint('Transaction error: $e');
      rethrow;
    }
  }

  /// Batch write pour des opérations multiples
  static Future<void> batchWriteTasks(List<WriteOperation> operations) async {
    try {
      final batch = firestore.batch();
      
      for (final operation in operations) {
        final docRef = firestore.collection('tasks').doc(operation.taskId);
        
        switch (operation.type) {
          case WriteOperationType.create:
            batch.set(docRef, operation.data);
            break;
          case WriteOperationType.update:
            batch.update(docRef, operation.data);
            break;
          case WriteOperationType.delete:
            batch.delete(docRef);
            break;
        }
      }
      
      await batch.commit();
      debugPrint('Batch write completed successfully');
    } catch (e) {
      debugPrint('Batch write error: $e');
      rethrow;
    }
  }
}

/// Classes pour les opérations batch
class WriteOperation {
  final String taskId;
  final WriteOperationType type;
  final Map<String, dynamic> data;

  WriteOperation({
    required this.taskId,
    required this.type,
    required this.data,
  });
}

enum WriteOperationType { create, update, delete }