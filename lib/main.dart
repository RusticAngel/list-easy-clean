// lib/main.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Your pages
import 'pages/login/login_widget.dart';
import 'pages/signup/signup_widget.dart';
import 'pages/creating/creating_widget.dart';
import 'pages/shopping_list/shopping_list_widget.dart';
import 'pages/referral/referral_screen.dart';  // ← Correct import (your actual file)

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://pwiyffxgzdscemxfdgsd.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB3aXlmZnhnemRzY2VteGZkZ3NkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM3MDgyMzcsImV4cCI6MjA3OTI4NDIzN30.wp3aKt9Cew2RUbO6trT8_WnbXq60KzYQTbLE2LCCvSc',
  );

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

    // REFERRAL PAGE — NOW 100% WORKING
    GoRoute(
      path: '/referral',
      builder: (context, state) => const ReferralScreen(),  // ← This matches your class name
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'List Easy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      routerConfig: _router,
    );
  }
}