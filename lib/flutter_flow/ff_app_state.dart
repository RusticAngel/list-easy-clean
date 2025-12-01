// lib/flutter_flow/ff_app_state.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class FFAppState extends ChangeNotifier {
  static FFAppState of(BuildContext context, {bool listen = true}) =>
      Provider.of<FFAppState>(context, listen: listen);

  bool isLoading = false;
  String? currentUserId;
  bool loggedIn = false; // ← must be here

  void setLoading(bool value) {
    isLoading = value;
    notifyListeners();
  }

  void setCurrentUserId(String? id) {
    currentUserId = id;
    notifyListeners();
  }

  void setLoggedIn(bool value) {
    loggedIn = value;
    notifyListeners();
  }
}