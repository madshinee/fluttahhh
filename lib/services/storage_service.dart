import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _onboardingKey = 'onboarding_completed';
  static const String _providerPriorityKey = 'provider_priority';
  static const String _activeProvidersKey = 'active_providers';

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<bool> isOnboardingCompleted() async {
    await init();
    return _prefs?.getBool(_onboardingKey) ?? false;
  }

  static Future<void> setOnboardingCompleted(bool completed) async {
    await init();
    await _prefs?.setBool(_onboardingKey, completed);
  }

  static Future<List<String>> getProviderPriority() async {
    await init();
    final priority = _prefs?.getStringList(_providerPriorityKey);
    return priority ?? ['supabase', 'firebase'];
  }

  static Future<void> setProviderPriority(List<String> priority) async {
    await init();
    await _prefs?.setStringList(_providerPriorityKey, priority);
  }

  static Future<List<String>> getActiveProviders() async {
    await init();
    final providers = _prefs?.getStringList(_activeProvidersKey);
    return providers ?? ['supabase', 'firebase'];
  }

  static Future<void> setActiveProviders(List<String> providers) async {
    await init();
    await _prefs?.setStringList(_activeProvidersKey, providers);
  }
}
