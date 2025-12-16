// lib/pages/signup/signup_widget.dart
// FINAL LAUNCH VERSION — CLEAN SIGN-UP WITH FRIENDLY ERRORS
// Graceful offline handling + KEYBOARD FIX (content scrolls above keyboard)

import 'dart:io'; // For SocketException
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignupWidget extends StatefulWidget {
  const SignupWidget({super.key});
  @override
  State<SignupWidget> createState() => _SignupWidgetState();
}

class _SignupWidgetState extends State<SignupWidget> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();
  bool isLoading = false;

  Future<void> _signup() async {
    // Basic validation
    if (passwordController.text != confirmController.text) {
      _showError('Passwords do not match');
      return;
    }

    if (nameController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }

    if (isLoading) return;
    setState(() => isLoading = true);

    try {
      await Supabase.instance.client.auth.signUp(
        email: emailController.text.trim(),
        password: passwordController.text,
        data: {'full_name': nameController.text.trim()},
      );

      // Success → go straight to create list
      if (mounted) context.go('/create');
    } on AuthException catch (e) {
      String message = 'Sign-up failed — please try again';

      if (e.message.toLowerCase().contains('already registered') ||
          e.message.toLowerCase().contains('user already')) {
        message = 'Email already registered — try signing in';
      } else if (e.message.toLowerCase().contains('password')) {
        message = 'Password too weak — try a longer one';
      }

      if (mounted) _showError(message);
    } on SocketException catch (_) {
      // No internet
      if (mounted) {
        _showError(
            'No internet connection — please check your network and try again');
      }
    } catch (e) {
      // Any other unexpected error
      if (mounted) {
        _showError('Sign-up failed — please try again');
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.deepOrange,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true, // Important for keyboard
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 32,
            right: 32,
            top: 32,
            bottom: MediaQuery.of(context).viewInsets.bottom +
                32, // Magic: pushes content above keyboard
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Create Account',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 40),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _input('Full Name'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _input('Email Address'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: _input('Password'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: _input('Confirm Password'),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: isLoading ? null : _signup,
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text('Sign Up',
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account? ',
                        style: TextStyle(color: Colors.white70)),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: const Text('Sign In',
                          style: TextStyle(
                              color: Colors.cyan, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      );
}
