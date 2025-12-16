// lib/pages/shopping_list/shopping_list_widget.dart
// FINAL LAUNCH VERSION — COMPACT + QUANTITY BUTTONS + OFFLINE SUPPORT
// Price editing improved: no leading zero, starts empty when price is 0
// Prices and total now show 2 decimals for cents (e.g. R40.95)

import 'dart:async';
import 'dart:convert'; // For jsonDecode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/currency_service.dart';

class ShoppingListWidget extends StatefulWidget {
  final int? listId; // Nullable for offline mode
  final bool isOffline; // Flag for offline mode

  const ShoppingListWidget({
    super.key,
    this.listId,
    this.isOffline = false,
  });

  @override
  State<ShoppingListWidget> createState() => _ShoppingListWidgetState();
}

class _ShoppingListWidgetState extends State<ShoppingListWidget> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> items = [];
  bool isLoading = true;

  late BannerAd _bannerAd;
  bool _isBannerAdReady = false;

  InterstitialAd? _interstitialAd;
  bool _isInterstitialReady = false;

  static const String _offlineListKey = 'offline_shopping_list';

  @override
  void initState() {
    super.initState();
    if (widget.isOffline) {
      _loadOfflineList();
    } else {
      loadItems();
    }
    _loadBannerAd();
    _loadInterstitialAd();
    _startBannerRefreshTimer();
  }

  Future<void> _loadOfflineList() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_offlineListKey);
    if (jsonString != null) {
      final List offlineItems = jsonDecode(jsonString);
      items = offlineItems.cast<Map<String, dynamic>>();
    }
    setState(() => isLoading = false);
  }

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
      if (mounted && _isBannerAdReady) _bannerAd.load();
    });
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: 'ca-app-pub-1957460965962453/7400405459',
      request: const AdRequest(),
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
        onAdDismissedFullScreenContent: (ad) async {
          ad.dispose();
          if (!widget.isOffline) {
            try {
              await supabase
                  .from('referrals')
                  .update({'successful': true})
                  .eq('referred_id', supabase.auth.currentUser!.id)
                  .not('successful', 'is', true)
                  .limit(1);
            } catch (_) {}
          }
          SystemNavigator.pop();
        },
        onAdFailedToShowFullScreenContent: (ad, err) {
          ad.dispose();
          SystemNavigator.pop();
        },
      );
      await _interstitialAd!.show();
      _interstitialAd = null;
      _isInterstitialReady = false;
    } else {
      if (!widget.isOffline) {
        try {
          await supabase
              .from('referrals')
              .update({'successful': true})
              .eq('referred_id', supabase.auth.currentUser!.id)
              .not('successful', 'is', true)
              .limit(1);
        } catch (_) {}
      }
      SystemNavigator.pop();
    }
  }

  Future<void> _shareList() async {
    if (widget.isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sharing requires internet')),
      );
      return;
    }

    try {
      final response = await supabase
          .from('shopping_lists')
          .update({'is_public': true})
          .eq('id', widget.listId!)
          .select('share_id')
          .single();

      final shareId = response['share_id'] as String;
      final shareLink = 'https://app.listeasy.com/share/$shareId';

      await Share.share(
        'Check out my shopping list on List Easy!\n'
        'Total: ${CurrencyService.instance.symbol}${total.toStringAsFixed(2)}\n\n'
        '$shareLink',
        subject:
            'My Shopping List - ${CurrencyService.instance.symbol}${total.toStringAsFixed(2)}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to share list')),
      );
    }
  }

  @override
  void dispose() {
    _bannerAd.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  Future<void> loadItems() async {
    if (widget.isOffline) {
      _loadOfflineList();
      return;
    }

    try {
      final data = await supabase
          .from('shopping_list_items')
          .select()
          .eq('list_id', widget.listId!)
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading list — check internet')),
        );
      }
    }
  }

  Future<void> toggleChecked(int index) async {
    if (widget.isOffline) {
      setState(() {
        final item = items[index];
        final newChecked = !(item['is_checked'] as bool? ?? false);
        item['is_checked'] = newChecked;
        items.sort(
            (a, b) => (a['is_checked'] ? 1 : 0) - (b['is_checked'] ? 1 : 0));
      });
      return;
    }

    final item = items[index];
    final newChecked = !(item['is_checked'] as bool? ?? false);

    await supabase
        .from('shopping_list_items')
        .update({'is_checked': newChecked}).eq('id', item['id']);

    if (mounted) {
      setState(() {
        items[index]['is_checked'] = newChecked;
        items.sort(
            (a, b) => (a['is_checked'] ? 1 : 0) - (b['is_checked'] ? 1 : 0));
      });
    }
  }

  Future<void> updateQuantity(int index, int delta) async {
    final item = items[index];
    final newQty = (item['quantity'] as int? ?? 1) + delta;
    if (newQty < 1) return;

    if (widget.isOffline) {
      setState(() => item['quantity'] = newQty);
      return;
    }

    await supabase
        .from('shopping_list_items')
        .update({'quantity': newQty}).eq('id', item['id']);

    if (mounted) setState(() => items[index]['quantity'] = newQty);
  }

  Future<void> updatePrice(int index, double newPrice) async {
    final item = items[index];

    if (widget.isOffline) {
      setState(() => item['price'] = newPrice);
      return;
    }

    await supabase
        .from('shopping_list_items')
        .update({'price': newPrice}).eq('id', item['id']);

    if (mounted) setState(() => items[index]['price'] = newPrice);
  }

  double get total => items.fold(
        0.0,
        (sum, item) =>
            sum +
            ((item['price'] as num?)?.toDouble() ?? 0.0) *
                (item['quantity'] as int? ?? 1),
      );

  // SMALLER QUANTITY BUTTONS
  Widget _qtyBtn(VoidCallback onTap, String text) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white54),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = CurrencyService.instance;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          widget.isOffline ? 'Offline Shopping List' : 'Your Shopping List',
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: widget.isOffline
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.cyan),
                  tooltip: 'Share this list',
                  onPressed: _shareList,
                ),
              ],
      ),
      floatingActionButton: widget.isOffline
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 90),
              child: FloatingActionButton.extended(
                backgroundColor: Colors.cyan,
                foregroundColor: Colors.black,
                onPressed: () async {
                  final controller = TextEditingController();
                  final newItem = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1C1C1E),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      title: const Text('Add extra item',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      content: TextField(
                        controller: controller,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Item name',
                          hintStyle: TextStyle(color: Colors.white54),
                          border: OutlineInputBorder(),
                          focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.cyan)),
                        ),
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel',
                                style: TextStyle(color: Colors.white70))),
                        TextButton(
                            onPressed: () =>
                                Navigator.pop(ctx, controller.text.trim()),
                            child: const Text('Add',
                                style: TextStyle(color: Colors.cyan))),
                      ],
                    ),
                  );

                  if (newItem != null && newItem.isNotEmpty && mounted) {
                    final userId = supabase.auth.currentUser!.id;
                    await supabase.from('shopping_list_items').insert({
                      'list_id': widget.listId!,
                      'user_id': userId,
                      'name': newItem,
                      'quantity': 1,
                      'price': 0.0,
                      'is_checked': false,
                    });
                    loadItems();
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Item',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
          : Column(
              children: [
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            widget.isOffline
                                ? 'Your offline list is empty'
                                : 'No items in this list yet.',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 18),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final item = items[i];
                            final checked =
                                item['is_checked'] as bool? ?? false;
                            final qty = item['quantity'] as int? ?? 1;
                            final price =
                                (item['price'] as num?)?.toDouble() ?? 0.0;
                            final name = item['name'] as String? ?? 'Unknown';

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: checked,
                                    activeColor: Colors.white,
                                    checkColor: Colors.black,
                                    side:
                                        const BorderSide(color: Colors.white54),
                                    onChanged: (_) => toggleChecked(i),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 17,
                                        color: checked
                                            ? Colors.white38
                                            : Colors.white,
                                        decoration: checked
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      _qtyBtn(() => updateQuantity(i, -1), '–'),
                                      Container(
                                        width: 44,
                                        alignment: Alignment.center,
                                        child: Text(
                                          '$qty',
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      _qtyBtn(() => updateQuantity(i, 1), '+'),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: () async {
                                      // Start empty if price is 0, otherwise show current value (with cents if any)
                                      final initialText = price > 0
                                          ? price.toStringAsFixed(2)
                                          : '';
                                      final controller = TextEditingController(
                                          text: initialText);

                                      final newPrice = await showDialog<double>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          backgroundColor:
                                              const Color(0xFF1C1C1E),
                                          title: Text('Set price for $name',
                                              style: const TextStyle(
                                                  color: Colors.white)),
                                          content: TextField(
                                            controller: controller,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                decimal: true),
                                            style: const TextStyle(
                                                color: Colors.white),
                                            autofocus: true,
                                            decoration: const InputDecoration(
                                              hintText:
                                                  'Enter amount (e.g. 40.95)',
                                              hintStyle: TextStyle(
                                                  color: Colors.white54),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx),
                                                child: const Text('Cancel',
                                                    style: TextStyle(
                                                        color:
                                                            Colors.white70))),
                                            TextButton(
                                              onPressed: () {
                                                final parsed = double.tryParse(
                                                    controller.text);
                                                Navigator.pop(
                                                    ctx, parsed ?? 0.0);
                                              },
                                              child: const Text('Save',
                                                  style: TextStyle(
                                                      color: Colors.cyan)),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (newPrice != null &&
                                          newPrice != price) {
                                        updatePrice(i, newPrice);
                                      }
                                    },
                                    child: Text(
                                      '${currency.symbol}${price.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 17),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Grand Total:',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                      Text(
                        '${currency.symbol}${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
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
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            title: const Text('Thank you for using List Easy!',
                                style: TextStyle(
                                    color: Colors.cyan,
                                    fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center),
                            content: Text(
                                'Your total: ${currency.symbol}${total.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 20),
                                textAlign: TextAlign.center),
                            actions: [
                              Center(
                                child: ElevatedButton(
                                  onPressed: _showInterstitialAndExit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(28)),
                                  ),
                                  child: const Text('Goodbye',
                                      style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28))),
                      child: const Text('Finish',
                          style: TextStyle(
                              color: Colors.black,
                              fontSize: 17,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                _isBannerAdReady
                    ? Container(
                        height: 100,
                        alignment: Alignment.center,
                        child: AdWidget(ad: _bannerAd))
                    : Container(
                        height: 100,
                        color: const Color(0xFF111111),
                        alignment: Alignment.center,
                        child: const Text('Loading ad...',
                            style: TextStyle(color: Colors.white38))),
              ],
            ),
    );
  }
}
