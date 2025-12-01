// lib/main.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'flutter_flow/ff_app_state.dart';
import 'pages/login/login_widget.dart';
import 'pages/signup/signup_widget.dart';
import 'pages/creating/creating_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://pwiyffxgzdscemxfdgsd.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB3aXlmZnhnemRzY2VteGZkZ3NkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM3MDgyMzcsImV4cCI6MjA3OTI4NDIzN30.wp3aKt9Cew2RUbO6trT8_WnbXq60KzYQTbLE2LCCvSc',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FFAppState()),
      ],
      child: MaterialApp.router(
        title: 'List Easy',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark),
        routerConfig: GoRouter(
          initialLocation: '/login',
          routes: [
            GoRoute(path: '/login', builder: (_, __) => const LoginWidget()),
            GoRoute(path: '/signup', builder: (_, __) => const SignupWidget()),
            GoRoute(path: '/creation', builder: (_, __) => const CreatingWidget()),
            GoRoute(path: '/home', builder: (_, __) => const CreatingWidget()),
          ],
        ),
      ),
    );
  }
}