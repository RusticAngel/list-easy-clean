// lib/pages/shopping_list/shopping_list_widget.dart
// FINAL LAUNCH VERSION — COMPACT + QUANTITY BUTTONS + FULL OFFLINE SUPPORT
// + Persist current list primarily via SharedPreferences ('current_shopping_draft')
//   → atomic, native-level writes → survives process kills much better
// + File as optional backup (still atomic rename)
// + Load: prefs first → file fallback → Supabase fallback
// + Clear draft ONLY on explicit Finish confirmation ("Goodbye")
// + Price editing improved + Total with 2 decimals
// UPDATED: Single Add Item button + Swipe-to-delete + All items visible
// + Tutorial (continues from creating, first launch only, smart scroll)
// NEW: Global currency auto-detection + price input validation (max 9,999,999.99)
// VISUAL POLISH: Tighter layout, smaller fonts, reduced padding, compact density
// SAFETY: PopScope intercepts back button + confirmation dialog
// FIXED: LateInitializationError, curly_braces_in_flow_control_structures, use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

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

  late ScrollController _scrollController;

  final GlobalKey _checkboxKey = GlobalKey();
  final GlobalKey _quantityMinusKey = GlobalKey();
  final GlobalKey _priceKey = GlobalKey();
  final GlobalKey _finishButtonKey = GlobalKey();

  SharedPreferences? _prefs; // Nullable - no late keyword

  String _deviceLocale = 'en_US';

  Future<String> get _draftFilePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/offline_current_list.json';
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    _deviceLocale =
        WidgetsBinding.instance.platformDispatcher.locale.toString();

    _loadBannerAd();
    _loadInterstitialAd();

    // Fire-and-forget prefs init
    _initPrefs();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTutorialIfNeeded();
    });
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    debugPrint('>>> SharedPreferences initialized successfully');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadList();
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
    if (!mounted) return;
    setState(() => isLoading = true);

    debugPrint('>>> ShoppingList: Starting loadList()');

    // FIX: Ensure prefs is ready before accessing it
    if (_prefs == null) {
      debugPrint('>>> Prefs not ready — awaiting initialization...');
      await _initPrefs();
    }

    // 1. Primary: SharedPreferences
    String? jsonString = _prefs!.getString('current_shopping_draft');

    if (jsonString != null && jsonString.isNotEmpty && jsonString != '[]') {
      debugPrint(
          '>>> ShoppingList: Found prefs draft (${jsonString.length} chars)');
      try {
        final List<dynamic> decoded = jsonDecode(jsonString);
        setState(() {
          items = decoded.map<Map<String, dynamic>>((dynamic raw) {
            final item = raw as Map<String, dynamic>? ?? {};
            final name = item['name'] as String? ??
                item['item_name'] as String? ??
                'Unnamed Item';
            return {
              'name': name,
              'quantity': (item['quantity'] as num?)?.toInt() ?? 1,
              'price': (item['price'] as num?)?.toDouble() ?? 0.0,
              'is_checked': item['is_checked'] as bool? ?? false,
              'id': item['id'] ?? DateTime.now().millisecondsSinceEpoch,
            };
          }).toList();
        });
        debugPrint(
            '>>> ShoppingList: Loaded ${items.length} items from prefs draft');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Resumed your unfinished shopping list')),
          );
        }

        setState(() => isLoading = false);
        return;
      } catch (e, stack) {
        debugPrint('>>> ShoppingList: Prefs draft parse error: $e\n$stack');
      }
    } else {
      debugPrint('>>> ShoppingList: No valid draft in prefs');
    }

    // 2. Fallback to file
    final file = File(await _draftFilePath);
    if (await file.exists()) {
      try {
        jsonString = await file.readAsString();
        debugPrint(
            '>>> ShoppingList: Read backup file (${jsonString.length} chars)');
      } catch (e) {
        debugPrint('>>> ShoppingList: File read error: $e');
      }
    } else {
      debugPrint('>>> ShoppingList: No draft file found');
    }

    if (jsonString != null && jsonString.isNotEmpty && jsonString != '[]') {
      debugPrint('>>> ShoppingList: Found saved draft in backup file');
      try {
        final List<dynamic> decoded = jsonDecode(jsonString);
        setState(() {
          items = decoded.map<Map<String, dynamic>>((dynamic raw) {
            final item = raw as Map<String, dynamic>? ?? {};
            final name = item['name'] as String? ??
                item['item_name'] as String? ??
                'Unnamed Item';
            return {
              'name': name,
              'quantity': (item['quantity'] as num?)?.toInt() ?? 1,
              'price': (item['price'] as num?)?.toDouble() ?? 0.0,
              'is_checked': item['is_checked'] as bool? ?? false,
              'id': item['id'] ?? DateTime.now().millisecondsSinceEpoch,
            };
          }).toList();
        });
        debugPrint(
            '>>> ShoppingList: Loaded ${items.length} items from backup file');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Resumed from backup file')),
          );
        }

        setState(() => isLoading = false);
        return;
      } catch (e, stack) {
        debugPrint('>>> ShoppingList: Backup file parse error: $e\n$stack');
      }
    } else {
      debugPrint('>>> ShoppingList: No valid draft in backup file');
    }

    // 3. Supabase fallback
    if (!widget.isOffline && widget.listId != null) {
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
          });
          await _saveCurrentListToJson();
        }
      } catch (e) {
        debugPrint('>>> Supabase load error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Offline mode — starting fresh')),
          );
        }
      }
    }

    if (mounted) {
      setState(() => isLoading = false);
    }
    debugPrint('>>> ShoppingList: Load finished (${items.length} items)');
    await _startTutorialIfNeeded();
  }

  Future<void> _saveCurrentListToJson() async {
    // Guard: ensure prefs is ready
    if (_prefs == null) {
      debugPrint('>>> Prefs not ready before save — awaiting...');
      await _initPrefs();
    }

    final jsonString = jsonEncode(items);

    try {
      // Primary save to SharedPreferences
      await _prefs!.setString('current_shopping_draft', jsonString);
      debugPrint(
          '>>> Saved to SharedPrefs (${items.length} items) | length: ${jsonString.length} chars');

      // Optional file backup (atomic rename)
      final path = await _draftFilePath;
      final tempPath = '$path.tmp';
      final tempFile = File(tempPath);

      await tempFile.writeAsString(jsonString);
      final sink = tempFile.openWrite(mode: FileMode.append);
      await sink.flush();
      await sink.close();
      await tempFile.rename(path);

      debugPrint('>>> Backup file atomic save OK | path: $path');

      // Verify
      final after = await File(path).readAsString();
      debugPrint('>>> Verify backup file: ${after.length} chars');
    } catch (e) {
      debugPrint('>>> Save failed: $e');
    }
  }

  Future<void> toggleChecked(int index) async {
    if (items.isEmpty || index >= items.length) return;

    final item = items[index];
    final newChecked = !(item['is_checked'] as bool? ?? false);

    if (!widget.isOffline && widget.listId != null) {
      try {
        await supabase
            .from('shopping_list_items')
            .update({'is_checked': newChecked}).eq('id', item['id']);
      } catch (e) {
        debugPrint('>>> Supabase toggle error: $e');
      }
    }

    if (!mounted) return;

    setState(() {
      items[index]['is_checked'] = newChecked;
      items.sort(
          (a, b) => (a['is_checked'] ? 1 : 0) - (b['is_checked'] ? 1 : 0));
    });
    await _saveCurrentListToJson();
  }

  Future<void> updateQuantity(int index, int delta) async {
    if (items.isEmpty || index >= items.length) return;

    final item = items[index];
    final newQty = (item['quantity'] as int? ?? 1) + delta;
    if (newQty < 1) return;

    if (!widget.isOffline && widget.listId != null) {
      try {
        await supabase
            .from('shopping_list_items')
            .update({'quantity': newQty}).eq('id', item['id']);
      } catch (e) {
        debugPrint('>>> Supabase quantity error: $e');
      }
    }

    if (!mounted) return;

    setState(() => items[index]['quantity'] = newQty);
    await _saveCurrentListToJson();
  }

  Future<void> updatePrice(int index, double newPrice) async {
    if (items.isEmpty || index >= items.length) return;

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

    final item = items[index];

    if (!widget.isOffline && widget.listId != null) {
      try {
        await supabase
            .from('shopping_list_items')
            .update({'price': newPrice}).eq('id', item['id']);
      } catch (e) {
        debugPrint('>>> Supabase price error: $e');
      }
    }

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

  Future<void> _shareList() async {
    if (widget.isOffline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sharing requires internet')),
        );
      }
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
      debugPrint('>>> Share error: $e');
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
          if (mounted) SystemNavigator.pop();
        },
        onAdFailedToShowFullScreenContent: (ad, err) async {
          ad.dispose();
          await _updateReferralStatus();
          if (mounted) SystemNavigator.pop();
        },
      );
      await _interstitialAd!.show();
      _interstitialAd = null;
      _isInterstitialReady = false;
    } else {
      await _updateReferralStatus();
      if (mounted) SystemNavigator.pop();
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
      if (!widget.isOffline && widget.listId != null) {
        try {
          final userId = supabase.auth.currentUser!.id;
          await supabase.from('shopping_list_items').insert({
            'list_id': widget.listId!,
            'user_id': userId,
            'name': newItem,
            'quantity': 1,
            'price': 0.0,
            'is_checked': false,
          });
        } catch (e) {
          debugPrint('>>> Supabase add extra error: $e');
        }
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
      await _saveCurrentListToJson();
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
          'Thank you for using List Easy!',
          style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        content: Text(
          'Your total: ${formatPrice(total)}',
          style: const TextStyle(color: Colors.white, fontSize: 18),
          textAlign: TextAlign.center,
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () async {
                // Guard prefs before clear
                if (_prefs == null) {
                  await _initPrefs();
                }

                await _prefs!.remove('current_shopping_draft');
                debugPrint('>>> Finish confirmed → prefs draft cleared');

                final file = File(await _draftFilePath);
                if (await file.exists()) {
                  await file.delete();
                  debugPrint('>>> Finish confirmed → backup file cleared');
                }

                if (!mounted) return;

                // ignore: use_build_context_synchronously
                Navigator.pop(ctx);
                _showInterstitialAndExit();
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
            title: const Text('Exit without finishing?',
                style: TextStyle(color: Colors.white)),
            content: const Text(
                'Your current list progress is saved automatically and will resume next time.'),
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
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: items.isEmpty
                          ? const Center(
                              child: Text(
                                'No items yet — add from the previous screen or resume your draft!',
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
                                final name =
                                    item['name'] as String? ?? 'Unknown';

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
                                    setState(() => items.removeAt(i));
                                    _saveCurrentListToJson();
                                  },
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
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
                                              onChanged: (_) =>
                                                  toggleChecked(i),
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
                                              _qtyBtn(
                                                  () => updateQuantity(i, -1),
                                                  '–'),
                                            Container(
                                              width: 36,
                                              alignment: Alignment.center,
                                              child: Text(
                                                '$qty',
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            _qtyBtn(() => updateQuantity(i, 1),
                                                '+'),
                                          ],
                                        ),
                                        const SizedBox(width: 8),
                                        if (i == 0)
                                          Showcase(
                                            key: _priceKey,
                                            title: "Add prices",
                                            description:
                                                "Tap to enter price — total updates instantly",
                                            child: GestureDetector(
                                              onTap: () =>
                                                  _editPriceDialog(i, price),
                                              child: Text(
                                                formatPrice(price),
                                                style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 15),
                                              ),
                                            ),
                                          )
                                        else
                                          GestureDetector(
                                            onTap: () =>
                                                _editPriceDialog(i, price),
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
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
                        child: Showcase(
                          key: _finishButtonKey,
                          title: "All done?",
                          description:
                              "Tap Finish to see your total and wrap up!",
                          child: ElevatedButton(
                            onPressed: _confirmFinish,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28)),
                            ),
                            child: const Text('Finish',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ),
                    if (_isBannerAdReady)
                      Container(
                        height: 100,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        child: AdWidget(ad: _bannerAd),
                      )
                    else
                      Container(
                        height: 100,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        color: const Color(0xFF111111),
                        alignment: Alignment.center,
                        child: const Text('Loading ad...',
                            style: TextStyle(color: Colors.white38)),
                      ),
                    const SizedBox(height: 8),
                    const Text('Built with Grok by xAI',
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
