// lib/app_state.dart

import 'package:supabase_flutter/supabase_flutter.dart';

/// Singleton app state – clean & simple
class AppState {
  // Private constructor + singleton pattern
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  // Supabase client (available everywhere)
  final supabase = Supabase.instance.client;

  // If you ever need secure storage in the future, just uncomment:
  // late final FlutterSecureStorage _secureStorage;
  //
  // Future<void> initSecureStorage() async {
  //   _secureStorage = const FlutterSecureStorage();
  // }
}

// Global instance (the one you already use all over the app)
final appState = AppState();