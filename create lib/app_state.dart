import 'package:flutter/material.dart';

class FFAppState extends ChangeNotifier {
  static final FFAppState _instance = FFAppState._internal();

  factory FFAppState() {
    return _instance;
  }

  FFAppState._internal();

  List<dynamic> templist = [];

  void update(VoidCallback callback) {
    callback();
    notifyListeners();
  }
}