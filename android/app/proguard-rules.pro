# =============================================
# Custom ProGuard rules for List Easy
# =============================================

# 1. Permanent fix for missing androidx.window.sidecar classes
#    (prevents NoClassDefFoundError on Huawei/Oppo/older devices)
-dontwarn androidx.window.sidecar.**
-dontwarn androidx.window.extensions.**
-keep class androidx.window.** { *; }
-keep class androidx.window.sidecar.** { *; }

# 2. Supabase — keep everything safe
-keep class com.supabase.** { *; }
-keep class io.supabase.** { *; }
-dontwarn com.supabase.**
-dontwarn io.supabase.**

# 3. RevenueCat (if you're using it — keep if present, remove if not)
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

# 4. Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# 5. Kotlin coroutines — safe keep for main dispatcher
-keepclassmembers class kotlinx.coroutines.internal.MainDispatcherFactory {
    *** getLoadPriority();
}

# 6. General Flutter & app safety (optional but recommended)
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
-keep class com.rusticangel.list_easy.** { *; }  # Your package name