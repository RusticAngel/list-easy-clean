// lib/main.dart
// FINAL + GLOBAL CURRENCY + CLEAN THEME + FULL OFFLINE SUPPORT + PUSH NOTIFICATIONS
// FIXED: Draft popup moved to CreatingWidget (reliable localizations)
// No root-level draft check anymore — simpler & crash-free
// UPDATED: Router now points /share/:shareId to editable SharedShoppingListWidget

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:showcaseview/showcaseview.dart';

import 'pages/login/login_widget.dart';
import 'pages/signup/signup_widget.dart';
import 'pages/creating/creating_widget.dart';
import 'pages/shopping_list/shopping_list_widget.dart';
import 'pages/referral/referral_screen.dart';
import 'pages/share/shared_shopping_list_widget.dart'; // ← NEW: editable shared list
import 'services/currency_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    debugPrint('Starting Supabase initialization...');
    await Supabase.initialize(
      url: 'https://pwiyffxgzdscemxfdgsd.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB3aXlmZnhnemRzY2VteGZkZ3NkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM3MDgyMzcsImV4cCI6MjA3OTI4NDIzN30.wp3aKt9Cew2RUbO6trT8_WnbXq60KzYQTbLE2LCCvSc',
    );
    debugPrint('Supabase initialized successfully');
  } catch (e, stack) {
    debugPrint('Supabase init failed: $e\n$stack');
  }

  try {
    debugPrint('Starting CurrencyService init...');
    await CurrencyService.instance.init();
    debugPrint('CurrencyService initialized');
  } catch (e, stack) {
    debugPrint('CurrencyService init failed: $e\n$stack');
  }

  try {
    debugPrint('Initializing OneSignal...');
    OneSignal.initialize("84e06ac2-ee74-4943-8185-e5f433dc87cb");
    OneSignal.Notifications.requestPermission(true);
    debugPrint('OneSignal initialized');
  } catch (e, stack) {
    debugPrint('OneSignal init failed: $e\n$stack');
  }

  try {
    OneSignal.User.addTagWithKey("first_launch", "true");
    OneSignal.User.addTagWithKey("has_created_list", "false");
    debugPrint('OneSignal tags added');
  } catch (e) {
    debugPrint('OneSignal tags failed: $e');
  }

  runApp(const MyApp());
}

class OfflineBanner extends StatefulWidget {
  final Widget child;

  const OfflineBanner({super.key, required this.child});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkInitialConnectivity();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      setState(() {
        _isOffline = results.contains(ConnectivityResult.none);
      });
    });
  }

  Future<void> _checkInitialConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() {
        _isOffline = results.contains(ConnectivityResult.none);
      });
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isOffline)
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.orangeAccent.withAlpha(230),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Offline Mode — Changes saved locally',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        final currentLocation = GoRouterState.of(context).matchedLocation;
        final isAuthRoute = currentLocation.startsWith('/login') ||
            currentLocation.startsWith('/signup');

        if (isAuthRoute) {
          return child;
        } else {
          return OfflineBanner(child: child);
        }
      },
      routes: [
        GoRoute(
          path: '/',
          redirect: (context, state) {
            final loggedIn = Supabase.instance.client.auth.currentUser != null;
            return loggedIn ? '/create' : '/signup';
          },
        ),
        GoRoute(
            path: '/signup', builder: (context, state) => const SignupWidget()),
        GoRoute(
            path: '/login', builder: (context, state) => const LoginWidget()),
        GoRoute(
            path: '/create',
            builder: (context, state) => const CreatingWidget()),
        GoRoute(
          path: '/shoppingList',
          builder: (context, state) {
            final queryParams = state.uri.queryParameters;
            if (queryParams['offline'] == 'true') {
              return const ShoppingListWidget(isOffline: true);
            }
            final listIdStr = queryParams['listId'];
            if (listIdStr == null) {
              return const CreatingWidget();
            }
            final listId = int.tryParse(listIdStr);
            return ShoppingListWidget(listId: listId);
          },
        ),
        GoRoute(
            path: '/referral',
            builder: (context, state) => const ReferralScreen()),
        GoRoute(
          path: '/share/:shareId',
          builder: (context, state) {
            final shareId = state.pathParameters['shareId']!;
            return SharedShoppingListWidget(
                shareId: shareId); // ← UPDATED: editable shared list
          },
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    backgroundColor: Colors.black,
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 80, color: Colors.redAccent),
          const SizedBox(height: 16),
          const Text(
            'Page not found',
            style: TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            state.error.toString(),
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.go('/'),
            child: const Text('Go Home'),
          ),
        ],
      ),
    ),
  ),
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      builder: (context) => MaterialApp.router(
        title: 'List Easy',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.cyan,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            elevation: 0,
            centerTitle: true,
          ),
        ),
        routerConfig: _router,
      ),
    );
  }
}
