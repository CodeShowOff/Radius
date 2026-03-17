# Flutter specific rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.plugin.editing.** { *; }

# Flutter Blue Plus rules (required for release builds)
-keep class com.lib.flutter_blue_plus.* { *; }

# Firebase rules
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Keep Bluetooth related classes
-keep class no.nordicsemi.** { *; }
-keep class android.bluetooth.** { *; }

# Crashlytics
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# Keep Parcelables
-keepclassmembers class * implements android.os.Parcelable {
    static ** CREATOR;
}

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Play Core (for deferred components / dynamic feature delivery)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Suppress missing Firebase Performance URLConnection class referenced by libraries
-dontwarn com.google.firebase.perf.network.FirebasePerfUrlConnection
