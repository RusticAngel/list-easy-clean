// lib/pages/shopping_list/shopping_list_widget.dart
// FINAL LAUNCH VERSION — COMPACT + QUANTITY BUTTONS + FULL OFFLINE SUPPORT
// + Persist current list to JSON (save on every change) + Load on open + Clear on Finish
// + Price editing improved + Total with 2 decimals
// UPDATED: Single Add Item button + Swipe-to-delete + All items visible
// + Tutorial (continues from creating, first launch only, smart scroll)
// NEW: Global currency auto-detection + price input validation (max 9,999,999.99)
// VISUAL POLISH: Tighter layout, smaller fonts, reduced padding, compact density (inspired by clean screenshot style)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:intl/intl.dart'; // For currency formatting

class ShoppingListWidget extends StatefulWidget {
  final int? listId;
  final bool isOffline;

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

  static const String _offlineCurrentListKey = 'offline_current_list';

  late ScrollController _scrollController;

  final GlobalKey _checkboxKey = GlobalKey();
  final GlobalKey _quantityMinusKey = GlobalKey();
  final GlobalKey _priceKey = GlobalKey();
  final GlobalKey _finishButtonKey = GlobalKey();

  // Cache device locale for currency formatting
  String _deviceLocale = 'en_US'; // Default fallback

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    // Get device locale once for consistent formatting
    // ignore: deprecated_member_use
    _deviceLocale = WidgetsBinding.instance.window.locale.toString();

    _loadList();
    _loadBannerAd();
    _loadInterstitialAd();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTutorialIfNeeded();
    });
  }

  Future<void> _startTutorialIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final creatingShown = prefs.getBool('tutorial_shown') ?? false;
    final shoppingComplete =
        prefs.getBool('shopping_tutorial_complete') ?? false;

    if (creatingShown && !shoppingComplete && mounted && items.isNotEmpty) {
      ShowCaseWidget.of(context).startShowCase([
        _checkboxKey,
        _quantityMinusKey,
        _priceKey,
        _finishButtonKey,
      ]);

      await prefs.setBool('shopping_tutorial_complete', true);
    }
  }

  Future<void> _loadList() async {
    if (widget.isOffline || widget.listId == null) {
      await _loadPersistedJsonList();
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
        _startTutorialIfNeeded();
        await _saveCurrentListToJson();
      }
    } catch (e) {
      await _loadPersistedJsonList();
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offline mode — using saved list')),
        );
      }
    }
  }

  Future<void> _loadPersistedJsonList() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_offlineCurrentListKey);
    if (jsonString != null) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonString);
        items = decoded.cast<Map<String, dynamic>>();
      } catch (e) {
        items = [];
      }
    } else {
      items = [];
    }
    if (mounted) {
      setState(() => isLoading = false);
      _startTutorialIfNeeded();
    }
  }

  Future<void> _saveCurrentListToJson() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(items);
    await prefs.setString(_offlineCurrentListKey, jsonString);
  }

  Future<void> _clearPersistedJsonList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_offlineCurrentListKey);
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
      await _saveCurrentListToJson();
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
      await _saveCurrentListToJson();
    }
  }

  Future<void> updateQuantity(int index, int delta) async {
    final item = items[index];
    final newQty = (item['quantity'] as int? ?? 1) + delta;
    if (newQty < 1) return;

    if (widget.isOffline) {
      setState(() => item['quantity'] = newQty);
      await _saveCurrentListToJson();
      return;
    }

    await supabase
        .from('shopping_list_items')
        .update({'quantity': newQty}).eq('id', item['id']);

    if (mounted) {
      setState(() => items[index]['quantity'] = newQty);
      await _saveCurrentListToJson();
    }
  }

  Future<void> updatePrice(int index, double newPrice) async {
    final item = items[index];

    // Validate max price
    const double maxPrice = 9999999.99;
    if (newPrice > maxPrice) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Price cannot exceed ${NumberFormat.simpleCurrency(locale: _deviceLocale).format(maxPrice)}',
            ),
          ),
        );
      }
      return;
    }

    if (widget.isOffline) {
      setState(() => item['price'] = newPrice);
      await _saveCurrentListToJson();
      return;
    }

    await supabase
        .from('shopping_list_items')
        .update({'price': newPrice}).eq('id', item['id']);

    if (mounted) {
      setState(() => items[index]['price'] = newPrice);
      await _saveCurrentListToJson();
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
        width: 24, // Smaller for compact look
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
        'Total: ${formatPrice(total)}\n\n'
        '$shareLink',
        subject: 'My Shopping List - ${formatPrice(total)}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to share list')),
        );
      }
    }
  }

  Future<void> _showInterstitialAndExit() async {
    if (_isInterstitialReady && _interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) async {
          ad.dispose();
          await _updateReferralStatus();
          await _clearPersistedJsonList();
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
      await _updateReferralStatus();
      await _clearPersistedJsonList();
      SystemNavigator.pop();
    }
  }

  Future<void> _updateReferralStatus() async {
    if (widget.isOffline) return;

    try {
      final userId = supabase.auth.currentUser!.id;

      final referral = await supabase
          .from('referrals')
          .select('lists_completed, successful')
          .eq('referred_id', userId)
          .maybeSingle();

      if (referral == null || (referral['successful'] as bool? ?? false)) {
        return;
      }

      int completed = (referral['lists_completed'] as int?) ?? 0;
      completed += 1;

      await supabase
          .from('referrals')
          .update({'lists_completed': completed}).eq('referred_id', userId);

      if (completed >= 2) {
        await supabase
            .from('referrals')
            .update({'successful': true}).eq('referred_id', userId);
      }
    } catch (e) {
      debugPrint('Referral update error: $e');
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

  @override
  void dispose() {
    _scrollController.dispose();
    _bannerAd.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          widget.isOffline ? 'Offline Shopping List' : 'Your Shopping List',
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: widget.isOffline
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.cyan, size: 22),
                  tooltip: 'Share this list',
                  onPressed: _shareList,
                ),
              ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyan))
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Items List - Tighter padding
                  Padding(
                    padding: const EdgeInsets.all(16), // Reduced from 20
                    child: items.isEmpty
                        ? const Center(
                            child: Text(
                              'No items yet — add from the previous screen!',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: items.length,
                            itemBuilder: (context, i) {
                              final item = items[i];
                              final checked =
                                  item['is_checked'] as bool? ?? false;
                              final qty = item['quantity'] as int? ?? 1;
                              final price =
                                  (item['price'] as num?)?.toDouble() ?? 0.0;
                              final name = item['name'] as String? ?? 'Unknown';

                              return Dismissible(
                                key: Key(item['id']?.toString() ?? name),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  color: Colors.red,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 16),
                                  child: const Icon(Icons.delete,
                                      color: Colors.white, size: 20),
                                ),
                                onDismissed: (_) {
                                  setState(() {
                                    items.removeAt(i);
                                  });
                                  _saveCurrentListToJson();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 6), // Reduced from 8
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      if (i == 0)
                                        Showcase(
                                          key: _checkboxKey,
                                          title: "Check off items",
                                          description:
                                              "Tap to mark as bought — moves to bottom",
                                          child: Checkbox(
                                            value: checked,
                                            activeColor: Colors.white,
                                            checkColor: Colors.black,
                                            side: const BorderSide(
                                                color: Colors.white38),
                                            onChanged: (_) => toggleChecked(i),
                                          ),
                                        )
                                      else
                                        Checkbox(
                                          value: checked,
                                          activeColor: Colors.white,
                                          checkColor: Colors.black,
                                          side: const BorderSide(
                                              color: Colors.white38),
                                          onChanged: (_) => toggleChecked(i),
                                        ),
                                      const SizedBox(
                                          width: 8), // Reduced from 12
                                      Expanded(
                                        child: Text(
                                          name,
                                          style: TextStyle(
                                            fontSize: 15, // Reduced from 17
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
                                          if (i == 0)
                                            Showcase(
                                              key: _quantityMinusKey,
                                              title: "Adjust quantity",
                                              description:
                                                  "Use – and + to change how many",
                                              child: _qtyBtn(
                                                  () => updateQuantity(i, -1),
                                                  '–'),
                                            )
                                          else
                                            _qtyBtn(() => updateQuantity(i, -1),
                                                '–'),
                                          Container(
                                            width: 36, // Reduced from 44
                                            alignment: Alignment.center,
                                            child: Text(
                                              '$qty',
                                              style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize:
                                                      14, // Reduced from 17
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          _qtyBtn(
                                              () => updateQuantity(i, 1), '+'),
                                        ],
                                      ),
                                      const SizedBox(
                                          width: 8), // Reduced from 12
                                      if (i == 0)
                                        Showcase(
                                          key: _priceKey,
                                          title: "Add prices",
                                          description:
                                              "Tap to enter price — total updates instantly",
                                          child: GestureDetector(
                                            onTap: () async {
                                              final initialText = price > 0
                                                  ? price.toStringAsFixed(2)
                                                  : '';
                                              final controller =
                                                  TextEditingController(
                                                      text: initialText);

                                              final newPrice =
                                                  await showDialog<double>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  backgroundColor:
                                                      const Color(0xFF1C1C1E),
                                                  title: Text(
                                                      'Set price for $name',
                                                      style: const TextStyle(
                                                          color: Colors.white)),
                                                  content: TextField(
                                                    controller: controller,
                                                    keyboardType:
                                                        const TextInputType
                                                            .numberWithOptions(
                                                            decimal: true),
                                                    style: const TextStyle(
                                                        color: Colors.white),
                                                    autofocus: true,
                                                    decoration:
                                                        const InputDecoration(
                                                            hintText:
                                                                'Enter amount (e.g. 40.95)',
                                                            hintStyle: TextStyle(
                                                                color: Colors
                                                                    .white54)),
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(ctx),
                                                        child: const Text(
                                                            'Cancel',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .white70))),
                                                    TextButton(
                                                      onPressed: () {
                                                        final parsed =
                                                            double.tryParse(
                                                                controller
                                                                    .text);
                                                        if (parsed != null &&
                                                            parsed >
                                                                9999999.99) {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                'Price cannot exceed ${formatPrice(9999999.99)}',
                                                              ),
                                                            ),
                                                          );
                                                          return;
                                                        }
                                                        Navigator.pop(
                                                            ctx, parsed ?? 0.0);
                                                      },
                                                      child: const Text('Save',
                                                          style: TextStyle(
                                                              color:
                                                                  Colors.cyan)),
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
                                              formatPrice(price),
                                              style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize:
                                                      15), // Reduced from 17
                                            ),
                                          ),
                                        )
                                      else
                                        GestureDetector(
                                          onTap: () async {
                                            final initialText = price > 0
                                                ? price.toStringAsFixed(2)
                                                : '';
                                            final controller =
                                                TextEditingController(
                                                    text: initialText);

                                            final newPrice =
                                                await showDialog<double>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                backgroundColor:
                                                    const Color(0xFF1C1C1E),
                                                title: Text(
                                                    'Set price for $name',
                                                    style: const TextStyle(
                                                        color: Colors.white)),
                                                content: TextField(
                                                  controller: controller,
                                                  keyboardType:
                                                      const TextInputType
                                                          .numberWithOptions(
                                                          decimal: true),
                                                  style: const TextStyle(
                                                      color: Colors.white),
                                                  autofocus: true,
                                                  decoration: const InputDecoration(
                                                      hintText:
                                                          'Enter amount (e.g. 40.95)',
                                                      hintStyle: TextStyle(
                                                          color:
                                                              Colors.white54)),
                                                ),
                                                actions: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(ctx),
                                                      child: const Text(
                                                          'Cancel',
                                                          style: TextStyle(
                                                              color: Colors
                                                                  .white70))),
                                                  TextButton(
                                                    onPressed: () {
                                                      final parsed =
                                                          double.tryParse(
                                                              controller.text);
                                                      if (parsed != null &&
                                                          parsed > 9999999.99) {
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              'Price cannot exceed ${formatPrice(9999999.99)}',
                                                            ),
                                                          ),
                                                        );
                                                        return;
                                                      }
                                                      Navigator.pop(
                                                          ctx, parsed ?? 0.0);
                                                    },
                                                    child: const Text('Save',
                                                        style: TextStyle(
                                                            color:
                                                                Colors.cyan)),
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
                  // Grand Total - Tighter container
                  Container(
                    margin: const EdgeInsets.fromLTRB(
                        16, 16, 16, 0), // Reduced margins
                    padding: const EdgeInsets.all(16), // Reduced padding
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius:
                          BorderRadius.circular(12), // Slightly smaller radius
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Grand Total:',
                            style: TextStyle(
                                fontSize: 16, // Reduced from 18
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                        Text(
                          formatPrice(total),
                          style: const TextStyle(
                              fontSize: 18, // Reduced from 20
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16), // Reduced from 24

                  // Add Item button - Slightly smaller
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50, // Reduced from 56
                      child: ElevatedButton.icon(
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
                                    hintStyle:
                                        TextStyle(color: Colors.white54)),
                              ),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Cancel',
                                        style:
                                            TextStyle(color: Colors.white70))),
                                TextButton(
                                  onPressed: () => Navigator.pop(
                                      ctx, controller.text.trim()),
                                  child: const Text('Add',
                                      style: TextStyle(color: Colors.cyan)),
                                ),
                              ],
                            ),
                          );

                          if (newItem != null &&
                              newItem.isNotEmpty &&
                              mounted) {
                            final userId = supabase.auth.currentUser!.id;
                            await supabase.from('shopping_list_items').insert({
                              'list_id': widget.listId!,
                              'user_id': userId,
                              'name': newItem,
                              'quantity': 1,
                              'price': 0.0,
                              'is_checked': false,
                            });
                            await _loadList();
                            await _saveCurrentListToJson();
                          }
                        },
                        icon: const Icon(Icons.add,
                            color: Colors.black, size: 20),
                        label: const Text('Add Item',
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyan,
                            shape: const StadiumBorder()),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16), // Reduced from 24

                  // Finish button - Slightly smaller
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    child: SizedBox(
                      height: 50, // Reduced from 56
                      width: double.infinity,
                      child: Showcase(
                        key: _finishButtonKey,
                        title: "All done?",
                        description:
                            "Tap Finish to see your total and wrap up!",
                        child: ElevatedButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF1C1C1E),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20)),
                                title: const Text(
                                    'Thank you for using List Easy!',
                                    style: TextStyle(
                                        color: Colors.cyan,
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center),
                                content: Text(
                                    'Your total: ${formatPrice(total)}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 18),
                                    textAlign: TextAlign.center),
                                actions: [
                                  Center(
                                    child: ElevatedButton(
                                      onPressed: _showInterstitialAndExit,
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(28))),
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
                                  fontSize: 16, // Reduced from 17
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),

                  // Banner ad - Keep height but reduce margin
                  if (_isBannerAdReady)
                    Container(
                        height: 100,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        child: AdWidget(ad: _bannerAd))
                  else
                    Container(
                        height: 100,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        color: const Color(0xFF111111),
                        alignment: Alignment.center,
                        child: const Text('Loading ad...',
                            style: TextStyle(color: Colors.white38))),

                  const SizedBox(height: 8),

                  const Text('Built with Grok by xAI',
                      style: TextStyle(
                          fontSize: 10, // Slightly smaller
                          color: Colors.white54,
                          fontWeight: FontWeight.w300),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
    );
  }
}
