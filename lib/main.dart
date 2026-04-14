import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'constants/app_colors.dart';
import 'pages/auth_wrapper.dart';
import 'pages/page_reset_password.dart';
import 'pages/page_onboarding.dart';
import 'services/supabase_service.dart';
import 'services/firebase_service.dart';
import 'services/storage_service.dart';
import 'services/sync_service.dart';
import 'services/error_reporting_service.dart';
import 'services/data_provider_service.dart';
import 'services/offline_service.dart';
import 'services/offline_sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');

    // 1. Firebase - doit être initialisé avant Crashlytics
    try {
      await FirebaseService.initialize();
    } catch (e) {
      debugPrint('Firebase initialization error: $e');
    }

    // 2. Error reporting
    await ErrorReportingService.initialize();
    await ErrorReportingService.setCustomKey(
        'app_start_time', DateTime.now().toIso8601String());

    // 3. Handlers globaux Crashlytics ──
    if (!kIsWeb) {
      // Erreurs Flutter (widgets, rendering...)
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

      // Erreurs async non catchées
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }

    // 4. Storage service
    await StorageService.init();

    // 5. Data provider service (utilise la configuration des providers)
    await DataProviderService.initialize();

    // 5. Supabase
    await SupabaseService.initialize();

    // Firebase déjà initialisé plus haut

    // 7. Offline database
    await OfflineService.initialize();

    // 6. Sync service
    await SyncService.initialize();

    // 7. Offline sync service (gestion des opérations offline)
    await OfflineSyncService.initialize();

    await ErrorReportingService.reportMessage(
        'Tous les services initialisés avec succès');
  } catch (e, stackTrace) {
    await ErrorReportingService.reportError(
      e, stackTrace,
      context: {'phase': 'initialization'},
      fatal: true,
    );
    debugPrint('Erreur d\'initialisation: $e');
  }

  runApp(const TranspoXApp());
}

class TranspoXApp extends StatelessWidget {
  const TranspoXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TranspoX',
      home: const AuthWrapper(),
      routes: {
        '/reset-password': (context) => const PageResetPassword(),
      },
      theme: ThemeData(
        fontFamily: 'NotoSans',
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: const Color(0xFFFFB347),
          surface: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            foregroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.inputBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.inputBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: AppColors.textDark,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: AppColors.textDark),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return null;
          }),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }
}
