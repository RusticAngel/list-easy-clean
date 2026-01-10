// lib/pages/creating/creating_widget.dart
// FINAL + TAP REMOVES ITEM + SMART SEARCH + FREQUENCY SORT + FULL OFFLINE SUPPORT
// + Persist in-progress creation to JSON + Load on open + Clear on success
// + Graceful offline handling + OneSignal tag + KEYBOARD FIX
// FIXED: Removed unwanted auto-scroll (no tutorial needed)
// + Single Add Item button + Swipe-to-delete + All items visible

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:showcaseview/showcaseview.dart';

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

  static const String _offlineCreationKey = 'offline_current_list_creation';

  late ScrollController _scrollController;

  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _addButtonKey = GlobalKey();
  final GlobalKey _previousSectionKey = GlobalKey();
  final GlobalKey _selectedSectionKey = GlobalKey();
  final GlobalKey _referButtonKey = GlobalKey();
  final GlobalKey _readyButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    _loadEverything();
    _loadBannerAd();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTutorialIfNeeded();
      // Auto-scroll removed permanently as requested
    });
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
                          'item_name': item['item_name'] as String,
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
    } catch (e) {
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
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_offlineCreationKey);
    if (jsonString != null) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonString);
        selectedItems = decoded.cast<Map<String, dynamic>>();
      } catch (e) {
        selectedItems = [];
      }
    } else {
      selectedItems = [];
    }
    if (mounted) {
      setState(() {
        filteredPreviousItems = previousItems;
      });
    }
  }

  Future<void> _saveCreationToJson() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(selectedItems);
    await prefs.setString(_offlineCreationKey, jsonString);
  }

  Future<void> _clearPersistedCreation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_offlineCreationKey);
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
                        'name': i['item_name'],
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
    } catch (e) {
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
                fontSize: 24,
                fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        physics: const ClampingScrollPhysics(),
        children: [
          Showcase(
            key: _previousSectionKey,
            title: "Smart suggestions",
            description: "Your frequent buys appear here — tap to add fast!",
            overlayColor: Colors.black.withAlpha(204),
            tooltipBackgroundColor: const Color(0xFF2A2A2A),
            titleTextStyle: const TextStyle(
                color: Colors.cyan, fontSize: 20, fontWeight: FontWeight.bold),
            descTextStyle: const TextStyle(color: Colors.white, fontSize: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16)),
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
                            style: const TextStyle(color: Colors.white),
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
                      const SizedBox(width: 12),
                      Showcase(
                        key: _addButtonKey,
                        title: "Tap to add",
                        description: "Or press Enter — quick!",
                        child: ElevatedButton.icon(
                          onPressed: () => addToSelected(searchController.text),
                          icon: const Icon(Icons.add, color: Colors.black),
                          label: const Text('Add',
                              style: TextStyle(color: Colors.black)),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyan,
                              shape: const StadiumBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Previous Items',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 140,
                    child: filteredPreviousItems.isEmpty
                        ? const Center(
                            child: Text('No matching items',
                                style: TextStyle(color: Colors.white38)))
                        : ListView.builder(
                            itemCount: filteredPreviousItems.length,
                            itemBuilder: (context, i) {
                              final itemName = filteredPreviousItems[i];
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: GestureDetector(
                                  onTap: () => addToSelected(itemName),
                                  onLongPress: () =>
                                      removeFromHistory(itemName),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFF222222),
                                        borderRadius:
                                            BorderRadius.circular(30)),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                            child: Text(itemName,
                                                style: const TextStyle(
                                                    color: Colors.white70))),
                                        const Icon(Icons.swipe,
                                            size: 18, color: Colors.white38),
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
          const SizedBox(height: 20),
          Showcase(
            key: _selectedSectionKey,
            title: "Your shopping list",
            description:
                "Double-check items here. Swipe to delete. Saves automatically!",
            overlayColor: Colors.black.withAlpha(204),
            tooltipBackgroundColor: const Color(0xFF2A2A2A),
            titleTextStyle: const TextStyle(
                color: Colors.cyan, fontSize: 20, fontWeight: FontWeight.bold),
            descTextStyle: const TextStyle(color: Colors.white, fontSize: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Selected Items',
                      style: TextStyle(color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 12),
                  selectedItems.isEmpty
                      ? const Center(
                          child: Text(
                              'Start adding items — saves automatically!',
                              style: TextStyle(color: Colors.white54)))
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: selectedItems.length,
                          itemBuilder: (context, i) {
                            final item = selectedItems[i];
                            return Dismissible(
                              key: Key(item['item_name']),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: Colors.red,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(Icons.delete,
                                    color: Colors.white),
                              ),
                              onDismissed: (_) => removeSelected(i),
                              child: ListTile(
                                title: Text(item['item_name'] as String,
                                    style:
                                        const TextStyle(color: Colors.white)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () => removeSelected(i),
                                ),
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 20),
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
                                side: const BorderSide(color: Colors.cyan)),
                            child: const Text('Refer a Friend',
                                style: TextStyle(color: Colors.cyan)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Showcase(
                          key: _readyButtonKey,
                          title: "Ready to shop?",
                          description: "Tap when done — edit anytime!",
                          child: ElevatedButton(
                            onPressed: isLoading ? null : createListAndGo,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                shape: const StadiumBorder()),
                            child: isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.black, strokeWidth: 2))
                                : const Text('Ready to Shop',
                                    style: TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_isBannerAdReady)
                    SizedBox(height: 90, child: AdWidget(ad: _bannerAd))
                  else
                    Container(
                        height: 90,
                        color: const Color(0xFF111111),
                        alignment: Alignment.center,
                        child: const Text('Loading ad...',
                            style: TextStyle(color: Colors.white38))),
                  const SizedBox(height: 8),
                  const Text('Built with Grok by xAI',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                          fontWeight: FontWeight.w300),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 100),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF111111),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none),
        prefixIcon: const Icon(Icons.search, color: Colors.cyan),
        suffixIcon: searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.white54),
                onPressed: () {
                  searchController.clear();
                  setState(() => filteredPreviousItems = previousItems);
                },
              )
            : null,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      );

  @override
  void dispose() {
    _scrollController.dispose();
    searchController.dispose();
    _bannerAd.dispose();
    super.dispose();
  }
}
