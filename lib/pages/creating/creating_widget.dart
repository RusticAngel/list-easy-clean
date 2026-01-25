// lib/pages/creating/creating_widget.dart
// FINAL + TAP REMOVES ITEM + SMART SEARCH + FREQUENCY SORT + FULL OFFLINE SUPPORT
// + Persist in-progress creation to JSON file (reliable instant save)
// + Load on open + Clear on success
// + Graceful offline handling + OneSignal tag + KEYBOARD FIX
// FIXED: Removed unwanted auto-scroll
// + Single Add Item button + Swipe-to-delete + All items visible
// VISUAL POLISH: Tighter layout, smaller fonts, reduced padding
// FIXED: Draft popup uses correct file
// FIXED: Safe draft loading & rendering → no more null crashes
// FIXED: Continue now simply navigates to ShoppingList (draft loads from file)
// FIXED: Discard clears draft file and keeps user on fresh Creating page
// IMPROVED: File-based persistence (path_provider) for crash-proof saving

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:intl/intl.dart';
import 'package:flutter/scheduler.dart';

import 'package:list_easy/pages/shopping_list/shopping_list_widget.dart';

class CreatingWidget extends StatefulWidget {
  const CreatingWidget({super.key});

  @override
  State<CreatingWidget> createState() => _CreatingWidgetState();
}

class _CreatingWidgetState extends State<CreatingWidget> {
  final supabase = Supabase.instance.client;
  final searchController = TextEditingController();

  List<String> previousItems = [];
  List<String> filteredPreviousItems = [];
  List<Map<String, dynamic>> selectedItems = [];
  bool isLoading = false;

  late BannerAd _bannerAd;
  bool _isBannerAdReady = false;

  late ScrollController _scrollController;

  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _addButtonKey = GlobalKey();
  final GlobalKey _previousSectionKey = GlobalKey();
  final GlobalKey _selectedSectionKey = GlobalKey();
  final GlobalKey _referButtonKey = GlobalKey();
  final GlobalKey _readyButtonKey = GlobalKey();

  // File path for draft persistence (crash-resistant)
  Future<String> get _draftFilePath async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/offline_current_list.json';
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    _loadEverything();
    _loadBannerAd();

    _checkForUnfinishedDraft();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTutorialIfNeeded();
    });
  }

  Future<void> _checkForUnfinishedDraft() async {
    final file = File(await _draftFilePath);
    if (!await file.exists()) return;

    String jsonString;
    try {
      jsonString = await file.readAsString();
    } catch (_) {
      return;
    }

    if (jsonString.isEmpty || jsonString == '[]') return;

    List<dynamic> decoded;
    try {
      decoded = jsonDecode(jsonString);
      if (decoded.isEmpty) return;
    } catch (_) {
      return;
    }

    final loadedItems = decoded.map<Map<String, dynamic>>((dynamic raw) {
      final item = raw as Map<String, dynamic>? ?? {};
      final name = (item['item_name'] as String?) ??
          (item['name'] as String?) ??
          'Unnamed Item';
      return {
        'item_name': name,
        'quantity': (item['quantity'] as num?)?.toInt() ?? 1,
        'price': (item['price'] as num?)?.toDouble() ?? 0.0,
        ...item,
      };
    }).toList();

    double total = 0.0;
    for (var item in loadedItems) {
      total += (item['price'] as double) * (item['quantity'] as int);
    }

    if (!mounted) return;

    final formatter = NumberFormat.simpleCurrency(
      locale: WidgetsBinding.instance.platformDispatcher.locale.toString(),
    );

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Unfinished Shopping List',
            style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
        content: Text(
          'You have an unfinished list (total ${formatter.format(total)}).\n\n'
          'Continue shopping or start fresh?',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child:
                const Text('Discard', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'continue'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
            child:
                const Text('Continue', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (choice == 'discard') {
      if (await file.exists()) await file.delete();
      if (mounted) {
        setState(() => selectedItems = []);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft discarded — starting fresh')),
        );
      }
    } else if (choice == 'continue') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Resuming your list...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ShoppingListWidget()),
        );
      });
    }
  }

  Future<void> _startTutorialIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final tutorialShown = prefs.getBool('tutorial_shown') ?? false;

    if (!tutorialShown && mounted) {
      ShowCaseWidget.of(context).startShowCase([
        _searchKey,
        _addButtonKey,
        _previousSectionKey,
        _selectedSectionKey,
        _referButtonKey,
        _readyButtonKey,
      ]);

      await prefs.setBool('tutorial_shown', true);
    }
  }

  Future<void> _loadEverything() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final draft = await supabase
            .from('draft_lists')
            .select('items')
            .eq('user_id', userId)
            .maybeSingle();

        final past = await supabase
            .from('shopping_list_items')
            .select('name, buy_count')
            .eq('user_id', userId)
            .order('buy_count', ascending: false)
            .order('created_at', ascending: false)
            .limit(100);

        final seen = <String>{};
        previousItems = past
            .map<String>((e) => e['name'] as String)
            .where((name) => seen.add(name.toLowerCase()))
            .take(30)
            .toList();

        if (mounted) {
          setState(() {
            selectedItems = (draft?['items'] as List?)
                    ?.map((item) => {
                          'item_name':
                              item['item_name'] as String? ?? 'Unnamed',
                          'quantity': (item['quantity'] as num?)?.toInt() ?? 1,
                        })
                    .toList() ??
                [];
            filteredPreviousItems = previousItems;
          });
        }
        await _saveCreationToJson();
        return;
      }
    } catch (_) {
      // Offline fallback
    }

    await _loadPersistedCreation();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offline mode — using saved draft')),
      );
    }
  }

  Future<void> _loadPersistedCreation() async {
    final file = File(await _draftFilePath);
    if (!await file.exists()) {
      selectedItems = [];
      return;
    }

    String jsonString;
    try {
      jsonString = await file.readAsString();
    } catch (_) {
      selectedItems = [];
      return;
    }

    if (jsonString.isEmpty || jsonString == '[]') {
      selectedItems = [];
      return;
    }

    try {
      final List<dynamic> decoded = jsonDecode(jsonString);
      selectedItems = decoded.map<Map<String, dynamic>>((dynamic raw) {
        final item = raw as Map<String, dynamic>? ?? {};
        return {
          'item_name': (item['item_name'] as String?) ?? 'Unnamed Item',
          'quantity': (item['quantity'] as num?)?.toInt() ?? 1,
        };
      }).toList();
    } catch (_) {
      selectedItems = [];
    }

    if (mounted) {
      setState(() {
        filteredPreviousItems = previousItems;
      });
    }
  }

  Future<void> _saveCreationToJson() async {
    final file = File(await _draftFilePath);
    final jsonString = jsonEncode(selectedItems);

    try {
      await file.writeAsString(jsonString, mode: FileMode.write);
    } catch (_) {
      // Silent in production
    }
  }

  Future<void> _clearPersistedCreation() async {
    final file = File(await _draftFilePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  void addToSelected(String name) {
    if (name.trim().isEmpty) return;
    final trimmed = name.trim();
    final lower = trimmed.toLowerCase();

    setState(() {
      if (!selectedItems
          .any((i) => (i['item_name'] as String).toLowerCase() == lower)) {
        selectedItems.add({'item_name': trimmed, 'quantity': 1});
      }
      previousItems.removeWhere((item) => item.toLowerCase() == lower);
      filteredPreviousItems = previousItems;
    });

    _saveCreationToJson();
    searchController.clear();
  }

  void removeSelected(int index) {
    setState(() {
      selectedItems.removeAt(index);
    });
    _saveCreationToJson();
  }

  Future<void> removeFromHistory(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove from history?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('"$name" will no longer appear in suggestions.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.cyan))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        previousItems.remove(name);
        filteredPreviousItems = previousItems;
      });
    }
  }

  Future<void> createListAndGo() async {
    if (selectedItems.isEmpty || isLoading) return;
    setState(() => isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      int? listId;

      if (userId != null) {
        final listResp = await supabase
            .from('shopping_lists')
            .insert({
              'user_id': userId,
              'name':
                  'My List ${DateTime.now().toIso8601String().substring(0, 10)}'
            })
            .select()
            .single();

        listId = listResp['id'];

        await supabase.from('shopping_list_items').insert(
              selectedItems
                  .map((i) => {
                        'list_id': listId,
                        'user_id': userId,
                        'name': i['item_name'] as String,
                        'quantity': i['quantity'] ?? 1,
                        'price': 0.0,
                        'is_checked': false,
                      })
                  .toList(),
            );

        final itemNames =
            selectedItems.map((i) => i['item_name'] as String).toList();
        if (itemNames.isNotEmpty) {
          await supabase.rpc('increment_buy_count',
              params: {'p_user_id': userId, 'p_item_names': itemNames});
        }

        await supabase.from('draft_lists').delete().eq('user_id', userId);
        await _clearPersistedCreation();
        OneSignal.User.addTagWithKey("has_created_list", "true");
      }

      if (mounted) {
        if (listId != null) {
          context.go('/shoppingList?listId=$listId');
        } else {
          context.go('/shoppingList?offline=true');
        }
      }
    } catch (_) {
      if (mounted) _showNoInternetDialog();
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showNoInternetDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('No Internet', style: TextStyle(color: Colors.white)),
        content: const Text(
          'You\'re offline. Your list is saved locally and you can continue shopping.\nIt will sync when you\'re back online.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK', style: TextStyle(color: Colors.cyan))),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Creating my list',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        physics: const ClampingScrollPhysics(),
        children: [
          Showcase(
            key: _previousSectionKey,
            title: "Smart suggestions",
            description: "Your frequent buys appear here — tap to add fast!",
            overlayColor: Colors.black.withAlpha(204),
            tooltipBackgroundColor: const Color(0xFF2A2A2A),
            titleTextStyle: const TextStyle(
                color: Colors.cyan, fontSize: 18, fontWeight: FontWeight.bold),
            descTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Showcase(
                          key: _searchKey,
                          title: "Add items here",
                          description: "Type to search or add new items",
                          child: TextField(
                            controller: searchController,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 15),
                            decoration: _inputDecoration('Add item'),
                            onChanged: (value) {
                              setState(() {
                                if (value.isEmpty) {
                                  filteredPreviousItems = previousItems;
                                } else {
                                  final query = value.toLowerCase();
                                  filteredPreviousItems = previousItems
                                      .where((item) =>
                                          item.toLowerCase().contains(query))
                                      .toList()
                                    ..sort((a, b) {
                                      final aLower = a.toLowerCase();
                                      final bLower = b.toLowerCase();
                                      final aStarts =
                                          aLower.startsWith(query) ? 0 : 1;
                                      final bStarts =
                                          bLower.startsWith(query) ? 0 : 1;
                                      return aStarts.compareTo(bStarts);
                                    });
                                }
                              });
                            },
                            onSubmitted: (value) => addToSelected(value),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Showcase(
                        key: _addButtonKey,
                        title: "Tap to add",
                        description: "Or press Enter — quick!",
                        child: ElevatedButton.icon(
                          onPressed: () => addToSelected(searchController.text),
                          icon: const Icon(Icons.add,
                              color: Colors.black, size: 18),
                          label: const Text('Add',
                              style:
                                  TextStyle(color: Colors.black, fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyan,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              shape: const StadiumBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Previous Items',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 120,
                    child: filteredPreviousItems.isEmpty
                        ? const Center(
                            child: Text('No matching items',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 14)))
                        : ListView.builder(
                            itemCount: filteredPreviousItems.length,
                            itemBuilder: (context, i) {
                              final itemName = filteredPreviousItems[i];
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                child: GestureDetector(
                                  onTap: () => addToSelected(itemName),
                                  onLongPress: () =>
                                      removeFromHistory(itemName),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFF222222),
                                        borderRadius:
                                            BorderRadius.circular(24)),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                            child: Text(itemName,
                                                style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 14))),
                                        const Icon(Icons.swipe,
                                            size: 16, color: Colors.white38),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Showcase(
            key: _selectedSectionKey,
            title: "Your shopping list",
            description:
                "Double-check items here. Swipe to delete. Saves automatically!",
            overlayColor: Colors.black.withAlpha(204),
            tooltipBackgroundColor: const Color(0xFF2A2A2A),
            titleTextStyle: const TextStyle(
                color: Colors.cyan, fontSize: 18, fontWeight: FontWeight.bold),
            descTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Selected Items',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 8),
                  selectedItems.isEmpty
                      ? const Center(
                          child: Text(
                              'Start adding items — saves automatically!',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 14)))
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: selectedItems.length,
                          itemBuilder: (context, i) {
                            final item = selectedItems[i];
                            final itemName = (item['item_name'] as String?) ??
                                'Unnamed Item';

                            return Dismissible(
                              key: Key(
                                  itemName.isNotEmpty ? itemName : 'item_$i'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: Colors.red,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 16),
                                child: const Icon(Icons.delete,
                                    color: Colors.white, size: 20),
                              ),
                              onDismissed: (_) => removeSelected(i),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 0),
                                title: Text(
                                  itemName,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 15),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red, size: 20),
                                  onPressed: () => removeSelected(i),
                                ),
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Showcase(
                          key: _referButtonKey,
                          title: "Get free Premium",
                          description: "Refer friends — earn free months!",
                          child: ElevatedButton(
                            onPressed: () => context.push('/referral'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A1A1A),
                                side: const BorderSide(color: Colors.cyan),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12)),
                            child: const Text('Refer a Friend',
                                style: TextStyle(
                                    color: Colors.cyan, fontSize: 14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Showcase(
                          key: _readyButtonKey,
                          title: "Ready to shop?",
                          description: "Tap when done — edit anytime!",
                          child: ElevatedButton(
                            onPressed: isLoading ? null : createListAndGo,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: const StadiumBorder()),
                            child: isLoading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.black, strokeWidth: 2))
                                : const Text('Ready to Shop',
                                    style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_isBannerAdReady)
                    SizedBox(height: 80, child: AdWidget(ad: _bannerAd))
                  else
                    Container(
                        height: 80,
                        color: const Color(0xFF111111),
                        alignment: Alignment.center,
                        child: const Text('Loading ad...',
                            style: TextStyle(color: Colors.white38))),
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
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 80),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFF111111),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none),
        prefixIcon: const Icon(Icons.search, color: Colors.cyan, size: 20),
        suffixIcon: searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.white54, size: 20),
                onPressed: () {
                  searchController.clear();
                  setState(() => filteredPreviousItems = previousItems);
                },
              )
            : null,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      );

  @override
  void dispose() {
    _scrollController.dispose();
    searchController.dispose();
    _bannerAd.dispose();
    super.dispose();
  }
}
