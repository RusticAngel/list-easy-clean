// lib/main.dart
// FINAL + GLOBAL CURRENCY + CLEAN THEME

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pages/login/login_widget.dart';
import 'pages/signup/signup_widget.dart';
import 'pages/creating/creating_widget.dart';
import 'pages/shopping_list/shopping_list_widget.dart';
import 'pages/referral/referral_screen.dart';
import 'pages/share/share_list_page.dart';
import 'services/currency_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://pwiyffxgzdscemxfdgsd.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB3aXlmZnhnemRzY2VteGZkZ3NkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM3MDgyMzcsImV4cCI6MjA3OTI4NDIzN30.wp3aKt9Cew2RUbO6trT8_WnbXq60KzYQTbLE2LCCvSc',
  );

  await CurrencyService.instance.init();

  runApp(const MyApp());
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      redirect: (context, state) {
        final loggedIn = Supabase.instance.client.auth.currentUser != null;
        return loggedIn ? '/create' : '/login';
      },
    ),
    GoRoute(path: '/login', builder: (context, state) => const LoginWidget()),
    GoRoute(path: '/signup', builder: (context, state) => const SignupWidget()),
    GoRoute(path: '/create', builder: (context, state) => const CreatingWidget()),
    GoRoute(
      path: '/shoppingList',
      builder: (context, state) {
        final listId = int.parse(state.uri.queryParameters['listId']!);
        return ShoppingListWidget(listId: listId);
      },
    ),
    GoRoute(path: '/referral', builder: (context, state) => const ReferralScreen()),
    GoRoute(
      path: '/share/:shareId',
      builder: (context, state) {
        final shareId = state.pathParameters['shareId']!;
        return ShareListPage(shareId: shareId);
      },
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    backgroundColor: Colors.black,
    body: Center(
      child: Text('Page not found :(', style: TextStyle(color: Colors.white70, fontSize: 18)),
    ),
  ),
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'List Easy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}