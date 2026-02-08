// lib/pages/shopping_list/shopping_list_widget.dart
// FINAL LAUNCH VERSION — COMPACT + QUANTITY BUTTONS + FULL OFFLINE SUPPORT
// Ads placeholders added: banner at bottom (hidden until verification), interstitial only on Goodbye
// FIXED: All 'use_build_context_synchronously' warnings with mounted checks
// FIXED: Removed unused _showBannerPlaceholder field
// UPDATED: Banner placeholder hidden with comment block — uncomment when verified
// FIXED: Dead code warning removed by using comment instead of if (false)
// FIXED: WhatsApp sharing now sends ONE clean link (HTTPS shared list) — no double previews

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  final GlobalKey _checkboxKey = GlobalKey();
  final GlobalKey _quantityMinusKey = GlobalKey();
  final GlobalKey _priceKey = GlobalKey();
  final GlobalKey _finishButtonKey = GlobalKey();

  SharedPreferences? _prefs;

  String _deviceLocale = 'en_US';

  bool _isSharing = false;

  Future<String> get _draftFilePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/offline_current_list.json';
  }

  @override
  void initState() {
    super.initState();

    // Capture real device locale once
    _deviceLocale =
        WidgetsBinding.instance.platformDispatcher.locale.toString();

    _initPrefs();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Tutorial check moved here, but real start happens after load
    });
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadList();
  }

  Future<void> _startTutorialIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();

    // One-time migration from old flag name
    if (prefs.containsKey('shopping_tutorial_complete') &&
        !prefs.containsKey('shopping_tutorial_shown')) {
      final oldShown = prefs.getBool('shopping_tutorial_complete') ?? false;
      if (oldShown) {
        await prefs.setBool('shopping_tutorial_shown', true);
      }
      await prefs.remove('shopping_tutorial_complete');
    }

    // Persistent flag — true = never show again
    final tutorialShown = prefs.getBool('shopping_tutorial_shown') ?? false;

    if (tutorialShown || !mounted || items.isEmpty) return;

    ShowCaseWidget.of(context).startShowCase([
      _checkboxKey,
      _quantityMinusKey,
      _priceKey,
      _finishButtonKey,
    ]);

    // Set flag immediately after starting
    await prefs.setBool('shopping_tutorial_shown', true);
  }

  Future<void> _loadList() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    if (_prefs == null) await _initPrefs();

    String? jsonString = _prefs!.getString('current_shopping_draft');

    if (jsonString != null && jsonString.isNotEmpty && jsonString != '[]') {
      try {
        final List<dynamic> decoded = jsonDecode(jsonString);
        if (!mounted) return;
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

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Resumed your unfinished shopping list')),
          );
        }

        if (!mounted) return;
        setState(() => isLoading = false);

        // Start tutorial after items are loaded (first launch only)
        _startTutorialIfNeeded();
        return;
      } catch (e) {
        // Silent fail — try backup file next
      }
    }

    final file = File(await _draftFilePath);
    if (await file.exists()) {
      try {
        jsonString = await file.readAsString();
        final List<dynamic> decoded = jsonDecode(jsonString);
        if (!mounted) return;
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

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Resumed from backup file')),
          );
        }

        if (!mounted) return;
        setState(() => isLoading = false);

        // Start tutorial after items are loaded (first launch only)
        _startTutorialIfNeeded();
        return;
      } catch (e) {
        // Silent fail — fall through to Supabase or empty
      }
    }

    if (!widget.isOffline && widget.listId != null) {
      try {
        final data = await supabase
            .from('shopping_list_items')
            .select()
            .eq('list_id', widget.listId!)
            .order('is_checked', ascending: true)
            .order('created_at');

        if (!mounted) return;
        setState(() {
          items = List<Map<String, dynamic>>.from(data);
        });
        await _saveCurrentListToJson();

        if (!mounted) return;
        setState(() => isLoading = false);

        // Start tutorial after items are loaded (first launch only)
        _startTutorialIfNeeded();
        return;
      } catch (e) {
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
  }

  Future<void> _saveCurrentListToJson() async {
    if (_prefs == null) await _initPrefs();

    final jsonString = jsonEncode(items);

    try {
      await _prefs!.setString('current_shopping_draft', jsonString);

      final path = await _draftFilePath;
      final tempPath = '$path.tmp';
      final tempFile = File(tempPath);

      await tempFile.writeAsString(jsonString);
      await tempFile.rename(path);
    } catch (e) {
      // Silent fail — local backup is best-effort
    }
  }

  Future<void> toggleChecked(int index) async {
    if (index < 0 || index >= items.length) return;

    final item = items[index];
    final newChecked = !(item['is_checked'] as bool? ?? false);

    if (!widget.isOffline && widget.listId != null) {
      try {
        await supabase
            .from('shopping_list_items')
            .update({'is_checked': newChecked}).eq('id', item['id']);
      } catch (_) {}
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
    if (index < 0 || index >= items.length) return;

    final item = items[index];
    final newQty = (item['quantity'] as int? ?? 1) + delta;
    if (newQty < 1) return;

    if (!widget.isOffline && widget.listId != null) {
      try {
        await supabase
            .from('shopping_list_items')
            .update({'quantity': newQty}).eq('id', item['id']);
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() => items[index]['quantity'] = newQty);
    await _saveCurrentListToJson();
  }

  Future<void> updatePrice(int index, double newPrice) async {
    if (index < 0 || index >= items.length) return;

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
      } catch (_) {}
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
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
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

    if (_isSharing) return;

    if (!mounted) return;
    setState(() => _isSharing = true);

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.cyan),
                ),
                SizedBox(width: 12),
                Text('Preparing share...'),
              ],
            ),
            duration: Duration(seconds: 10),
          ),
        );
      }

      final response = await supabase
          .from('shopping_lists')
          .update({'is_public': true})
          .eq('id', widget.listId!)
          .select('share_id')
          .single();

      final shareId = response['share_id'] as String;
      final shareLink =
          'https://app.listeasy.com/share/$shareId'; // ← Your real domain here

      final shareText = 'Check out my shopping list on List Easy!\n'
          'Total: ${formatPrice(total)}\n\n'
          'Tap to view: $shareLink\n\n'
          '(Opens in the app — or downloads List Easy if not installed yet)';

      await Share.share(
        shareText,
        subject: 'My Shopping List - ${formatPrice(total)}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('List shared successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to share — check internet and try again'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
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
    } catch (_) {}
  }

  @override
  void dispose() {
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
        } catch (_) {}
      }

      if (!mounted) return;
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
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
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
                if (!mounted) return;

                // Interstitial placeholder — would show real ad here later
                // For now: just a visual marker in code (no UI popup)
                // Replace with real interstitial show code after verification

                if (_prefs == null) await _initPrefs();

                await _prefs!.remove('current_shopping_draft');

                final file = File(await _draftFilePath);
                if (await file.exists()) await file.delete();

                if (!mounted) return;

                // ignore: use_build_context_synchronously
                Navigator.pop(dialogCtx);
                await _updateReferralStatus();

                if (mounted) SystemNavigator.pop();
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
              'Your current list progress is saved automatically and will resume next time.',
            ),
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

        if (shouldExit == true && mounted) {
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
                    icon: _isSharing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.cyan),
                          )
                        : const Icon(Icons.share, color: Colors.cyan, size: 22),
                    tooltip: 'Share this list',
                    onPressed: _isSharing ? null : _shareList,
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
                                    if (!mounted) return;
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
                    const SizedBox(height: 16),

                    // Banner placeholder — hidden until AdMob verification
                    // Uncomment the block below when ready to show real ads
                    /*
                    Container(
                      height: 60,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'Banner Ad Placeholder\n(Add real AdMob unit ID after verification)',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    */

                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }
}
