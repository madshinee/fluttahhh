# Firebase Crashlytics
-keep class com.google.firebase.crashlytics.** { *; }
-keep class com.google.firebase.** { *; }
-keep class io.flutter.plugins.firebase.crashlytics.** { *; }
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable

# Flutter Firebase Crashlytics specific
-keep class com.google.firebase.crashlytics.FlutterFirebaseCrashlyticsInternal { *; }
-keep class io.flutter.plugins.firebase.crashlytics.FlutterFirebaseCrashlyticsPlugin { *; }
-keep class io.flutter.plugins.firebase.crashlytics.FlutterFirebaseAppRegistrar { *; }

# Keep all model classes
-keep class com.example.flutter_application_1.** { *; }

# Keep all Flutter engine classes
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
