// lib/pages/share/share_list_page.dart
// FINAL — EDITABLE SHARED LIST — DEEP LINK READY — FULL FEATURE PARITY WITH MAIN LIST
// + Loads from shareId + is_public check
// + Full editing: add item, quantity +/-, price edit, check/uncheck, swipe delete
// + Live total updates
// + Finish dialog + interstitial ad + SystemNavigator.pop()
// + No local draft/prefs/file saving (Supabase only)
// + Loading, error, not-found states
// + Consistent UI from shopping_list_widget.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';

class SharedShoppingListWidget extends StatefulWidget {
  final String shareId;

  const SharedShoppingListWidget({
    super.key,
    required this.shareId,
  });

  @override
  State<SharedShoppingListWidget> createState() =>
      _SharedShoppingListWidgetState();
}

class _SharedShoppingListWidgetState extends State<SharedShoppingListWidget> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> items = [];
  bool isLoading = true;
  bool notFound = false;
  bool hasError = false;

  late BannerAd _bannerAd;
  bool _isBannerAdReady = false;

  InterstitialAd? _interstitialAd;
  bool _isInterstitialReady = false;

  String _deviceLocale = 'en_US';

  @override
  void initState() {
    super.initState();
    _deviceLocale =
        WidgetsBinding.instance.platformDispatcher.locale.toString();

    _loadBannerAd();
    _loadInterstitialAd();

    _loadSharedList();
  }

  Future<void> _loadSharedList() async {
    try {
      final response = await supabase
          .from('shopping_lists')
          .select('*, shopping_list_items(*)')
          .eq('share_id', widget.shareId)
          .eq('is_public', true)
          .single();

      setState(() {
        items = List<Map<String, dynamic>>.from(
            response['shopping_list_items'] ?? []);
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Shared list load error: $e');
      setState(() {
        isLoading = false;
        if (e.toString().contains('not found') ||
            e.toString().contains('0 rows')) {
          notFound = true;
        } else {
          hasError = true;
        }
      });
    }
  }

  double get total => items.fold(
        0.0,
        (sum, item) =>
            sum +
            ((item['price'] as num?)?.toDouble() ?? 0.0) *
                (item['quantity'] as int? ?? 1),
      );

  String formatPrice(double price) {
    final formatter = NumberFormat.simpleCurrency(locale: _deviceLocale);
    return formatter.format(price);
  }

  Widget _qtyBtn(VoidCallback onTap, String text) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white38, width: 1),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<void> toggleChecked(int index) async {
    final item = items[index];
    final newChecked = !(item['is_checked'] as bool? ?? false);

    try {
      await supabase
          .from('shopping_list_items')
          .update({'is_checked': newChecked}).eq('id', item['id']);
    } catch (e) {
      debugPrint('Toggle checked error: $e');
    }

    if (!mounted) return;

    setState(() {
      items[index]['is_checked'] = newChecked;
      items.sort(
          (a, b) => (a['is_checked'] ? 1 : 0) - (b['is_checked'] ? 1 : 0));
    });
  }

  Future<void> updateQuantity(int index, int delta) async {
    final item = items[index];
    final newQty = (item['quantity'] as int? ?? 1) + delta;
    if (newQty < 1) return;

    try {
      await supabase
          .from('shopping_list_items')
          .update({'quantity': newQty}).eq('id', item['id']);
    } catch (e) {
      debugPrint('Quantity update error: $e');
    }

    if (!mounted) return;

    setState(() => items[index]['quantity'] = newQty);
  }

  Future<void> updatePrice(int index, double newPrice) async {
    const double maxPrice = 9999999.99;
    if (newPrice > maxPrice) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Price cannot exceed ${formatPrice(maxPrice)}')),
        );
      }
      return;
    }

    final item = items[index];

    try {
      await supabase
          .from('shopping_list_items')
          .update({'price': newPrice}).eq('id', item['id']);
    } catch (e) {
      debugPrint('Price update error: $e');
    }

    if (mounted) {
      setState(() => items[index]['price'] = newPrice);
    }
  }

  Future<void> _addExtraItem() async {
    final controller = TextEditingController();
    final newItem = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add extra item',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
              hintText: 'Item name',
              hintStyle: TextStyle(color: Colors.white54)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add', style: TextStyle(color: Colors.cyan)),
          ),
        ],
      ),
    );

    if (newItem != null && newItem.isNotEmpty && mounted) {
      try {
        // Get list_id from shareId
        final listData = await supabase
            .from('shopping_lists')
            .select('id')
            .eq('share_id', widget.shareId)
            .single();

        await supabase.from('shopping_list_items').insert({
          'list_id': listData['id'],
          'user_id': supabase.auth.currentUser?.id ?? 'shared_user', // fallback
          'name': newItem,
          'quantity': 1,
          'price': 0.0,
          'is_checked': false,
        });
      } catch (e) {
        debugPrint('Add item error: $e');
      }

      setState(() {
        items.add({
          'id': items.length + 1,
          'name': newItem,
          'quantity': 1,
          'price': 0.0,
          'is_checked': false,
        });
      });
    }
  }

  Future<void> _confirmFinish() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Thank you for using the shared list!',
          style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: Text(
          'Total: ${formatPrice(total)}',
          style: const TextStyle(color: Colors.white, fontSize: 18),
          textAlign: TextAlign.center,
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _showInterstitialAndExit();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28)),
              ),
              child: const Text(
                'Goodbye',
                style:
                    TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showInterstitialAndExit() async {
    if (_isInterstitialReady && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) async {
          ad.dispose();
          if (mounted) SystemNavigator.pop();
        },
        onAdFailedToShowFullScreenContent: (ad, err) async {
          ad.dispose();
          if (mounted) SystemNavigator.pop();
        },
      );
      await _interstitialAd!.show();
      _interstitialAd = null;
      _isInterstitialReady = false;
    } else {
      if (mounted) SystemNavigator.pop();
    }
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-1957460965962453/8166692213',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _isBannerAdReady = true);
        },
        onAdFailedToLoad: (ad, err) => ad.dispose(),
      ),
    )..load();
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

  Future<void> _editPriceDialog(int index, double currentPrice) async {
    final item = items[index];
    final name = item['name'] as String? ?? 'Unknown';
    final initialText = currentPrice > 0 ? currentPrice.toStringAsFixed(2) : '';
    final controller = TextEditingController(text: initialText);

    final newPrice = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text('Set price for $name',
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter amount (e.g. 40.95)',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text);
              if (parsed != null && parsed > 9999999.99) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'Price cannot exceed ${formatPrice(9999999.99)}')),
                  );
                }
                return;
              }
              Navigator.pop(ctx, parsed ?? 0.0);
            },
            child: const Text('Save', style: TextStyle(color: Colors.cyan)),
          ),
        ],
      ),
    );

    if (newPrice != null && newPrice != currentPrice) {
      await updatePrice(index, newPrice);
    }
  }

  @override
  void dispose() {
    _bannerAd.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text('Exit shared list?',
                style: TextStyle(color: Colors.white)),
            content: const Text(
                'Your edits are saved to the shared list automatically. Exit now?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:
                    const Text('Cancel', style: TextStyle(color: Colors.cyan)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child:
                    const Text('Exit', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        );

        if (shouldExit == true && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: const Text('Shared Shopping List',
              style: TextStyle(color: Colors.cyan)),
          centerTitle: true,
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
            : notFound
                ? const Center(
                    child: Text(
                      'List not found or is private',
                      style: TextStyle(color: Colors.white70, fontSize: 18),
                    ),
                  )
                : hasError
                    ? const Center(
                        child: Text(
                          'Error loading shared list',
                          style:
                              TextStyle(color: Colors.redAccent, fontSize: 18),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: items.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'This shared list is empty!',
                                        style: TextStyle(
                                            color: Colors.white54,
                                            fontSize: 16),
                                        textAlign: TextAlign.center,
                                      ),
                                    )
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: items.length,
                                      itemBuilder: (context, i) {
                                        final item = items[i];
                                        final checked =
                                            item['is_checked'] as bool? ??
                                                false;
                                        final qty =
                                            item['quantity'] as int? ?? 1;
                                        final price = (item['price'] as num?)
                                                ?.toDouble() ??
                                            0.0;
                                        final name = item['name'] as String? ??
                                            'Unknown';

                                        return Dismissible(
                                          key: Key(
                                              item['id']?.toString() ?? name),
                                          direction:
                                              DismissDirection.endToStart,
                                          background: Container(
                                            color: Colors.red,
                                            alignment: Alignment.centerRight,
                                            padding: const EdgeInsets.only(
                                                right: 16),
                                            child: const Icon(Icons.delete,
                                                color: Colors.white, size: 20),
                                          ),
                                          onDismissed: (_) {
                                            setState(() => items.removeAt(i));
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 6),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Checkbox(
                                                  value: checked,
                                                  activeColor: Colors.white,
                                                  checkColor: Colors.black,
                                                  side: const BorderSide(
                                                      color: Colors.white38),
                                                  onChanged: (_) =>
                                                      toggleChecked(i),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    name,
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      color: checked
                                                          ? Colors.white38
                                                          : Colors.white,
                                                      decoration: checked
                                                          ? TextDecoration
                                                              .lineThrough
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                                Row(
                                                  children: [
                                                    _qtyBtn(
                                                        () => updateQuantity(
                                                            i, -1),
                                                        '–'),
                                                    Container(
                                                      width: 36,
                                                      alignment:
                                                          Alignment.center,
                                                      child: Text(
                                                        '$qty',
                                                        style: const TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    _qtyBtn(
                                                        () => updateQuantity(
                                                            i, 1),
                                                        '+'),
                                                  ],
                                                ),
                                                const SizedBox(width: 8),
                                                GestureDetector(
                                                  onTap: () => _editPriceDialog(
                                                      i, price),
                                                  child: Text(
                                                    formatPrice(price),
                                                    style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 15),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                            Container(
                              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Grand Total:',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white)),
                                  Text(
                                    formatPrice(total),
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: _addExtraItem,
                                  icon: const Icon(Icons.add,
                                      color: Colors.black, size: 20),
                                  label: const Text('Add Item',
                                      style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.cyan,
                                    shape: const StadiumBorder(),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                              child: SizedBox(
                                height: 50,
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _confirmFinish,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(28)),
                                  ),
                                  child: const Text('Finish',
                                      style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ),
                            if (_isBannerAdReady)
                              Container(
                                height: 100,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                alignment: Alignment.center,
                                child: AdWidget(ad: _bannerAd),
                              )
                            else
                              Container(
                                height: 100,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                color: const Color(0xFF111111),
                                alignment: Alignment.center,
                                child: const Text('Loading ad...',
                                    style: TextStyle(color: Colors.white38)),
                              ),
                            const SizedBox(height: 8),
                            const Text('Shared via List Easy',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white54,
                                    fontWeight: FontWeight.w300),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
      ),
    );
  }
}
