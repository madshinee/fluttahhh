import 'dart:io' show Platform, File;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

class ErrorReportingService {
  static bool _initialized = false;
  static const String _errorLogKey = 'error_logs';
  static const int _maxErrorLogs = 50;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Initialize Firebase Crashlytics
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);

      _initialized = true;
      debugPrint('Error reporting service initialized with Crashlytics');
    } catch (e) {
      debugPrint('Failed to initialize error reporting: $e');
    }
  }

  static Future<void> reportError(
      dynamic error,
      StackTrace? stackTrace, {
        Map<String, dynamic>? context,
        bool fatal = false,
      }) async {
    if (!_initialized) {
      await initialize();
    }

    final errorReport = {
      'timestamp': DateTime.now().toIso8601String(),
      'error': error.toString(),
      'stackTrace': stackTrace?.toString(),
      'context': context,
      'fatal': fatal,
      'platform': kIsWeb ? 'web' : Platform.operatingSystem,
    };

    // Log to console in debug mode
    if (kDebugMode) {
      debugPrint('=== ERROR REPORT ===');
      debugPrint('Error: $error');
      if (stackTrace != null) {
        debugPrint('Stack trace: $stackTrace');
      }
      if (context != null) {
        debugPrint('Context: $context');
      }
      debugPrint('===================');
    }

    try {
      // Send to Crashlytics
      List<Object> information = [];
      if (context != null) {
        for (final entry in context.entries) {
          information.add('${entry.key}: ${entry.value}');
        }
      }
      
      if (fatal) {
        await FirebaseCrashlytics.instance.recordError(
          error, 
          stackTrace,
          fatal: true,
          information: information,
        );
      } else {
        await FirebaseCrashlytics.instance.recordError(
          error, 
          stackTrace,
          information: information,
        );
      }

      // Store locally for fallback
      await _storeErrorLocally(errorReport);

      debugPrint('Error reported successfully to Crashlytics');
    } catch (e) {
      debugPrint('Failed to report error to Crashlytics: $e');
      // Fallback to local storage only
      await _storeErrorLocally(errorReport);
    }
  }

  static Future<void> reportMessage(String message, {Map<String, dynamic>? context}) async {
    if (!_initialized) {
      await initialize();
    }

    final logEntry = {
      'timestamp': DateTime.now().toIso8601String(),
      'message': message,
      'context': context,
      'level': 'INFO',
      'platform': kIsWeb ? 'web' : Platform.operatingSystem,
    };

    if (kDebugMode) {
      debugPrint('Message: $message');
      if (context != null) {
        debugPrint('Context: $context');
      }
      debugPrint('==========');
    }

    try {
      // Send to Crashlytics
      await FirebaseCrashlytics.instance.log('$message${context != null ? ' - $context' : ''}');

      await _storeErrorLocally(logEntry);
    } catch (e) {
      debugPrint('Failed to log message to Crashlytics: $e');
    }
  }

  static Future<void> setUserIdentifier(String userId) async {
    if (!_initialized) {
      await initialize();
    }

    try {
      // Set user ID in Crashlytics
      await FirebaseCrashlytics.instance.setUserIdentifier(userId);
      debugPrint('User identifier set: $userId');
    } catch (e) {
      debugPrint('Failed to set user identifier: $e');
    }
  }

  static Future<void> setCustomKey(String key, dynamic value) async {
    if (!_initialized) {
      await initialize();
    }

    try {
      // Set custom key in Crashlytics
      await FirebaseCrashlytics.instance.setCustomKey(key, value);
      debugPrint('Custom key set: $key = $value');
    } catch (e) {
      debugPrint('Failed to set custom key: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getStoredErrors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final errorJson = prefs.getStringList(_errorLogKey) ?? [];

      return errorJson
          .map((jsonStr) => jsonDecode(jsonStr) as Map<String, dynamic>)
          .toList();
    } catch (e) {
      debugPrint('Failed to retrieve stored errors: $e');
      return [];
    }
  }

  static Future<void> clearStoredErrors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_errorLogKey);
      debugPrint('Stored errors cleared');
    } catch (e) {
      debugPrint('Failed to clear stored errors: $e');
    }
  }

  static Future<void> exportErrorLogs() async {
    try {
      final errors = await getStoredErrors();
      if (errors.isEmpty) {
        debugPrint('No error logs to export');
        return;
      }

      final directory = await getApplicationDocumentsDirectory();
      final file = File(join(directory.path, 'error_logs_${DateTime.now().millisecondsSinceEpoch}.txt'));

      final buffer = StringBuffer();
      for (final error in errors) {
        buffer.writeln('=== Error Report ===');
        buffer.writeln('Timestamp: ${error['timestamp']}');
        buffer.writeln('Platform: ${error['platform']}');

        if (error['error'] != null) {
          buffer.writeln('Error: ${error['error']}');
        }

        if (error['message'] != null) {
          buffer.writeln('Message: ${error['message']}');
        }

        if (error['stackTrace'] != null) {
          buffer.writeln('Stack Trace: ${error['stackTrace']}');
        }

        if (error['context'] != null) {
          buffer.writeln('Context: ${error['context']}');
        }

        buffer.writeln('====================');
        buffer.writeln();
      }

      await file.writeAsString(buffer.toString());
      debugPrint('Error logs exported to: ${file.path}');
    } catch (e) {
      debugPrint('Failed to export error logs: $e');
    }
  }

  static Future<void> _storeErrorLocally(Map<String, dynamic> errorReport) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final errorLogs = prefs.getStringList(_errorLogKey) ?? [];

      // Add new error as JSON string
      errorLogs.add(jsonEncode(errorReport));

      // Keep only the last N errors
      if (errorLogs.length > _maxErrorLogs) {
        errorLogs.removeRange(0, errorLogs.length - _maxErrorLogs);
      }

      await prefs.setStringList(_errorLogKey, errorLogs);
    } catch (e) {
      debugPrint('Failed to store error locally: $e');
    }
  }
}
