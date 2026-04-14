import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'page_onboarding.dart';
import 'page_reset_password.dart';
import 'page_connexion.dart';
import 'page_tasks.dart';
import '../services/storage_service.dart';
import '../services/data_provider_service.dart';
import '../models/user.dart' as app_user;

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isInitialized = false;
  bool _showOnboarding = true;
  app_user.User? _currentUser;

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _handlePasswordResetLink();
  }

  Future<void> _initializeApp() async {
    await StorageService.init();
    
    // Check for existing session first
    await _checkExistingSession();
    
    final shouldShowOnboarding = await _shouldShowOnboarding();
    
    setState(() {
      _showOnboarding = shouldShowOnboarding;
      _isInitialized = true;
    });
  }

  Future<void> _checkExistingSession() async {
    try {
      // Check if user is already authenticated
      final currentUser = DataProviderService.currentUser;
      
      if (currentUser != null) {
        debugPrint(' User already authenticated: ${currentUser.email}');
        setState(() {
          _currentUser = currentUser;
        });
      } else {
        debugPrint(' No existing session found');
        
        // Check for offline cached user
        await _checkOfflineCachedUser();
      }
    } catch (e) {
      debugPrint(' Error checking existing session: $e');
    }
  }

  Future<void> _checkOfflineCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasCredentials = prefs.getBool('credentials_cached') ?? false;
      
      if (hasCredentials) {
        final cachedUserData = prefs.getString('cached_user_data');
        if (cachedUserData != null) {
          final user = app_user.User.fromJsonString(cachedUserData);
          debugPrint(' Found cached offline user: ${user.email}');
          setState(() {
            _currentUser = user;
          });
        }
      }
    } catch (e) {
      debugPrint(' Error checking offline cached user: $e');
    }
  }

  Future<bool> _shouldShowOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if it's the first launch (for analytics only)
      final firstLaunch = !prefs.containsKey('app_first_launch');
      if (firstLaunch) {
        await prefs.setBool('app_first_launch', true);
      }
      
      // Check if onboarding is completed
      final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
      
      // Show onboarding if not completed (removed firstLaunch condition)
      final shouldShow = !onboardingCompleted;
      
      debugPrint('Should show onboarding: $shouldShow (firstLaunch: $firstLaunch, completed: $onboardingCompleted)');
      return shouldShow;
    } catch (e) {
      debugPrint('Error checking onboarding: $e');
      return true; // Show onboarding by default if error
    }
  }

  Future<void> _completeOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_completed', true);
      debugPrint('Onboarding completed');
    } catch (e) {
      debugPrint('Error completing onboarding: $e');
    }
  }

  void _handlePasswordResetLink() {
    // Attendre que Supabase soit initialisé
    try {
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        final AuthChangeEvent event = data.event;
        
        if (event == AuthChangeEvent.passwordRecovery) {
          // L'utilisateur a cliqué sur le lien de réinitialisation
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/reset-password',
            (route) => false,
          );
        }
      });
    } catch (e) {
      debugPrint('Supabase not yet initialized: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Priority: Onboarding > Authenticated User > Login
    if (_showOnboarding) {
      return const PageOnboarding();
    }
    
    // If user is already authenticated, redirect to tasks
    if (_currentUser != null) {
      debugPrint(' Redirecting authenticated user to tasks page');
      return PageTasks(user: _currentUser!);
    }
    
    // Otherwise, show login page
    return const PageConnexion();
  }
}
