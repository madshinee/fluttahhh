import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/user.dart' as app_user;

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: dotenv.env['GOOGLE_CLIENT_ID_WEB'] ?? '', // Utiliser le Client ID Web
    scopes: [
      'email',
      'https://www.googleapis.com/auth/userinfo.profile',
    ],
  );

  // ── Connexion avec Google ───────────────────────────────────────────────────
  static Future<app_user.User?> signInWithGoogle() async {
    try {
      // Déconnexion d'abord pour éviter les conflits
      await _googleSignIn.signOut();

      // Tentative de connexion Google
      GoogleSignInAccount? googleAccount = await _googleSignIn.signIn();

      if (googleAccount == null) {
        return null; // L'utilisateur a annulé
      }

      // Récupérer les tokens Google
      final GoogleSignInAuthentication googleAuth = await googleAccount.authentication;

      // Vérifier que le idToken n'est pas null
      if (googleAuth.idToken == null) {
        throw Exception('Impossible d\'obtenir le token ID de Google');
      }

      // Connexion avec Supabase en utilisant le token Google
      final AuthResponse authResponse = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: googleAuth.idToken!,
      );

      if (authResponse.user == null) {
        throw Exception('Échec de l\'authentification Supabase');
      }

      // Créer un objet User à partir des infos Supabase
      final user = app_user.User.fromSupabaseUser(authResponse.user!);

      return user;
    } catch (e) {
      throw Exception('Erreur lors de la connexion Google: $e');
    }
  }

  // ── Déconnexion ─────────────────────────────────────────────────────────────
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      throw Exception('Erreur lors de la déconnexion Google: $e');
    }
  }

  // ── Vérifier si déjà connecté ─────────────────────────────────────────────────
  static Future<bool> isSignedIn() async {
    return await _googleSignIn.isSignedIn();
  }

  // ── Récupérer l'utilisateur actuel ─────────────────────────────────────────────
  static Future<GoogleSignInAccount?> getCurrentUser() async {
    return await _googleSignIn.currentUser;
  }
}
