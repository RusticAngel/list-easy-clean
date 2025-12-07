// lib/services/currency_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class CurrencyService {
  static final CurrencyService instance = CurrencyService._();
  CurrencyService._();

  String symbol = 'R'; // Default = South Africa

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('currency_symbol');
    if (saved != null) symbol = saved;
  }

  Future<void> setCurrency(String newSymbol) async {
    symbol = newSymbol;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currency_symbol', newSymbol);
  }
}