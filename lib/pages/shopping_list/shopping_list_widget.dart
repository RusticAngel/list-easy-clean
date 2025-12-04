// lib/pages/shopping_list/shopping_list_widget.dart
// FINAL + INTERSTITIAL ON EXIT + 60-sec banner refresh + ZERO ERRORS

import 'dart:async'; // ← NEW: for Timer
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class ShoppingListWidget extends StatefulWidget {
  final int listId;
  const ShoppingListWidget({super.key, required this.listId});

  @override
  State<ShoppingListWidget> createState() => _ShoppingListWidgetState();
}

class _ShoppingListWidgetState extends State<ShoppingListWidget> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> items = [];
  bool isLoading = true;

  // Banner
  late BannerAd _bannerAd;
  bool _isBannerAdReady = false;

  // Interstitial
  InterstitialAd? _interstitialAd;
  bool _isInterstitialReady = false;

  @override
  void initState() {
    super.initState();
    loadItems();
    _loadBannerAd();
    _loadInterstitialAd(); // Pre-load on page open
    _startBannerRefreshTimer();
  }

  // === BANNER ===
  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-1957460965962453/8166692213',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdReady = true),
        onAdFailedToLoad: (ad, err) => ad.dispose(),
      ),
    )..load();
  }

  void _startBannerRefreshTimer() {
    Timer.periodic(const Duration(seconds: 60), (timer) {
      if (mounted && _isBannerAdReady) {
        _bannerAd.load();
      }
    });
  }

  // === INTERSTITIAL ===
  void _loadInterstitialAd() {
    InterstitialAd.load(
adUnitId: 'ca-app-pub-1957460965962453/7400405459',      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialReady = true;
        },
        onAdFailedToLoad: (err) {
          _isInterstitialReady = false;
          _interstitialAd = null;
        },
      ),
    );
  }

  Future<void> _showInterstitialAndExit() async {
    if (_isInterstitialReady && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          SystemNavigator.pop(); // Close app
        },
        onAdFailedToShowFullScreenContent: (ad, err) {
          ad.dispose();
          SystemNavigator.pop(); // Still exit even if ad fails
        },
      );
      await _interstitialAd!.show();
      _interstitialAd = null;
      _isInterstitialReady = false;
    } else {
      // No ad ready → just exit
      SystemNavigator.pop();
    }
  }

  @override
  void dispose() {
    _bannerAd.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  Future<void> loadItems() async {
    try {
      final data = await supabase
          .from('shopping_list_items')
          .select()
          .eq('list_id', widget.listId)
          .order('is_checked', ascending: true)
          .order('created_at');

      if (mounted) {
        setState(() {
          items = List<Map<String, dynamic>>.from(data);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> toggleChecked(int index) async {
    final item = items[index];
    final newChecked = !(item['is_checked'] as bool? ?? false);

    await supabase
        .from('shopping_list_items')
        .update({'is_checked': newChecked})
        .eq('id', item['id']);

    if (mounted) {
      setState(() {
        items[index]['is_checked'] = newChecked;
        items.sort((a, b) => (a['is_checked'] ? 1 : 0) - (b['is_checked'] ? 1 : 0));
      });
    }
  }

  Future<void> updateQuantity(int index, int delta) async {
    final item = items[index];
    final newQty = (item['quantity'] as int? ?? 1) + delta;
    if (newQty < 1) return;

    await supabase
        .from('shopping_list_items')
        .update({'quantity': newQty})
        .eq('id', item['id']);

    if (mounted) setState(() => items[index]['quantity'] = newQty);
  }

  Future<void> updatePrice(int index, double newPrice) async {
    await supabase
        .from('shopping_list_items')
        .update({'price': newPrice})
        .eq('id', items[index]['id']);

    if (mounted) setState(() => items[index]['price'] = newPrice);
  }

  double get total => items.fold(
        0.0,
        (sum, item) =>
            sum +
            ((item['price'] as num?)?.toDouble() ?? 0.0) *
                (item['quantity'] as int? ?? 1),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Your Shopping List',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.share_outlined, color: Colors.white), onPressed: () {}),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
          : Column(
              children: [
                Expanded(
                  child: items.isEmpty
                      ? const Center(
                          child: Text(
                            'No items in this list yet.',
                            style: TextStyle(color: Colors.white54, fontSize: 18),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(20),
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final item = items[i];
                            final checked = item['is_checked'] as bool? ?? false;
                            final qty = item['quantity'] as int? ?? 1;
                            final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                            final name = item['name'] as String? ?? 'Unknown';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                              decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: checked,
                                    activeColor: Colors.white,
                                    checkColor: Colors.black,
                                    side: const BorderSide(color: Colors.white54),
                                    onChanged: (_) => toggleChecked(i),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 17,
                                        color: checked ? Colors.white54 : Colors.white,
                                        decoration: checked ? TextDecoration.lineThrough : null,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      _qtyBtn(() => updateQuantity(i, -1), '-'),
                                      SizedBox(width: 40, child: Center(child: Text('$qty', style: const TextStyle(color: Colors.white, fontSize: 16)))),
                                      _qtyBtn(() => updateQuantity(i, 1), '+'),
                                    ],
                                  ),
                                  const SizedBox(width: 20),
                                  GestureDetector(
                                    onTap: () async {
                                      final controller = TextEditingController(text: price.toStringAsFixed(0));
                                      final newPrice = await showDialog<double>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          backgroundColor: const Color(0xFF1C1C1E),
                                          title: Text('Set price for $name', style: const TextStyle(color: Colors.white)),
                                          content: TextField(
                                            controller: controller,
                                            keyboardType: TextInputType.number,
                                            style: const TextStyle(color: Colors.white),
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text) ?? price),
                                              child: const Text('Save', style: TextStyle(color: Colors.cyan)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (newPrice != null && newPrice != price) updatePrice(i, newPrice);
                                    },
                                    child: Text(
                                      'R${price.toStringAsFixed(0)}',
                                      style: const TextStyle(color: Colors.cyan, fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                // Grand Total
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Grand Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                      Text('R${total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                ),

                // Finish Button → NOW SHOWS INTERSTITIAL
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  child: SizedBox(
                    height: 56,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF1C1C1E),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: const Text('Thank you for using List Easy!',
                                style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                            content: Text('Your total: R${total.toStringAsFixed(0)}',
                                style: const TextStyle(color: Colors.white, fontSize: 20), textAlign: TextAlign.center),
                            actions: [
                              Center(
                                child: ElevatedButton(
                                  onPressed: _showInterstitialAndExit, // ← THIS IS THE MAGIC
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                                  ),
                                  child: const Text('Goodbye', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                      child: const Text('Finish', style: TextStyle(color: Colors.black, fontSize: 17, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),

                // Banner (refreshes every 60 sec)
                _isBannerAdReady
                    ? Container(
                        height: 100,
                        width: double.infinity,
                        alignment: Alignment.center,
                        child: AdWidget(ad: _bannerAd),
                      )
                    : Container(
                        height: 100,
                        width: double.infinity,
                        color: const Color(0xFF111111),
                        alignment: Alignment.center,
                        child: const Text('Loading ad...', style: TextStyle(color: Colors.white38)),
                      ),
              ],
            ),
    );
  }

  Widget _qtyBtn(VoidCallback onTap, String text) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(border: Border.all(color: Colors.white54), borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: Text(text, style: const TextStyle(fontSize: 20, color: Colors.white)),
      ),
    );
  }
}