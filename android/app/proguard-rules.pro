# Supabase — keep everything
-keep class com.supabase.** { *; }
-keep class io.supabase.** { *; }
-dontwarn com.supabase.**
-dontwarn io.supabase.**

# RevenueCat
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

# Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# Kotlin coroutines (just in case)
-keepclassmembers class kotlinx.coroutines.internal.MainDispatcherFactory { *** getLoadPriority(); }