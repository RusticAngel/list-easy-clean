// lib/pages/creating/creating_widget.dart
// FINAL + TAP REMOVES ITEM + SMART SEARCH + FREQUENCY SORT + PERFECT

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

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
  Timer? _bannerRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadEverything();
    _loadBannerAd();
  }

  Future<void> _loadEverything() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

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
  }

  Future<void> _saveDraft() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    if (selectedItems.isEmpty) {
      await supabase.from('draft_lists').delete().eq('user_id', userId);
      return;
    }

    await supabase.from('draft_lists').upsert({
      'user_id': userId,
      'items': selectedItems
          .map((i) => {
                'item_name': i['item_name'] as String,
                'quantity': i['quantity'] as int? ?? 1,
              })
          .cast<Map<String, Object?>>()
          .toList(),
    });
  }

  void addToSelected(String name) {
    if (name.trim().isEmpty) return;
    final trimmed = name.trim();
    final lower = trimmed.toLowerCase();

    setState(() {
      // Add to selected if not already there
      if (!selectedItems.any((i) => (i['item_name'] as String).toLowerCase() == lower)) {
        selectedItems.add({'item_name': trimmed, 'quantity': 1});
        _saveDraft();
      }

      // REMOVE FROM BOTH LISTS — THIS MAKES IT DISAPPEAR
      previousItems.removeWhere((item) => item.toLowerCase() == lower);
      filteredPreviousItems = previousItems;
    });

    searchController.clear();
  }

  void removeSelected(int index) {
    setState(() {
      selectedItems.removeAt(index);
      _saveDraft();
    });
  }

  Future<void> removeFromHistory(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove from history?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('"$name" will no longer appear in suggestions.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
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
      final userId = supabase.auth.currentUser!.id;
      final listResp = await supabase
          .from('shopping_lists')
          .insert({'user_id': userId, 'name': 'My List ${DateTime.now().toIso8601String().substring(0, 10)}'})
          .select()
          .single();

      final listId = listResp['id'];

      await supabase.from('shopping_list_items').insert(
        selectedItems.map((i) => {
          'list_id': listId,
          'user_id': userId,
          'name': i['item_name'],
          'quantity': i['quantity'] ?? 1,
          'price': 0.0,
          'is_checked': false,
        }).toList(),
      );

      // Increment buy_count
      final itemNames = selectedItems.map((i) => i['item_name'] as String).toList();
      if (itemNames.isNotEmpty) {
        await supabase.rpc('increment_buy_count', params: {
          'p_user_id': userId,
          'p_item_names': itemNames,
        });
      }

      await supabase.from('draft_lists').delete().eq('user_id', userId);

      if (mounted) context.go('/shoppingList?listId=$listId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-1957460965962453/8166692213',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            setState(() => _isBannerAdReady = true);
            _startBannerRefresh();
          }
        },
        onAdFailedToLoad: (ad, err) => ad.dispose(),
      ),
    )..load();
  }

  void _startBannerRefresh() {
    _bannerRefreshTimer?.cancel();
    _bannerRefreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (mounted && _isBannerAdReady) _bannerAd.load();
    });
  }

  @override
  void dispose() {
    _bannerAd.dispose();
    _bannerRefreshTimer?.cancel();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Creating my list',
          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Add item',
                            hintStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: const Color(0xFF111111),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
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
                          ),
                          onChanged: (value) {
                            setState(() {
                              if (value.isEmpty) {
                                filteredPreviousItems = previousItems;
                              } else {
                                final query = value.toLowerCase();
                                filteredPreviousItems = previousItems.where((item) {
                                  return item.toLowerCase().contains(query);
                                }).toList()
                                  ..sort((a, b) {
                                    final aLower = a.toLowerCase();
                                    final bLower = b.toLowerCase();
                                    final aStarts = aLower.startsWith(query) ? 0 : 1;
                                    final bStarts = bLower.startsWith(query) ? 0 : 1;
                                    return aStarts.compareTo(bStarts);
                                  });
                              }
                            });
                          },
                          onSubmitted: (value) => addToSelected(value),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => addToSelected(searchController.text),
                        icon: const Icon(Icons.add, color: Colors.black),
                        label: const Text('Add', style: TextStyle(color: Colors.black)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan, shape: const StadiumBorder()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Previous Items', style: TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 140,
                    child: filteredPreviousItems.isEmpty
                        ? const Center(child: Text('No matching items', style: TextStyle(color: Colors.white38)))
                        : ListView.builder(
                            itemCount: filteredPreviousItems.length,
                            itemBuilder: (context, i) {
                              final itemName = filteredPreviousItems[i];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: GestureDetector(
                                  onTap: () => addToSelected(itemName), // Taps work
                                  onLongPress: () => removeFromHistory(itemName),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    decoration: BoxDecoration(color: const Color(0xFF222222), borderRadius: BorderRadius.circular(30)),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(itemName, style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis),
                                        ),
                                        const Icon(Icons.swipe, size: 18, color: Colors.white38),
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

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Selected Items', style: TextStyle(color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: selectedItems.isEmpty
                        ? const Center(
                            child: Text(
                              'Start adding items — your list saves automatically!',
                              style: TextStyle(color: Colors.white54),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            itemCount: selectedItems.length,
                            itemBuilder: (context, i) => ListTile(
                              title: Text(selectedItems[i]['item_name'] as String, style: const TextStyle(color: Colors.white)),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => removeSelected(i),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => context.push('/referral'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A1A1A), side: const BorderSide(color: Colors.cyan)),
                    child: const Text('Refer a Friend', style: TextStyle(color: Colors.cyan)),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: isLoading ? null : createListAndGo,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: const StadiumBorder()),
                    child: isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Text('Ready to Shop', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 20),

                  if (_isBannerAdReady)
                    Container(height: 90, alignment: Alignment.center, child: AdWidget(ad: _bannerAd))
                  else
                    Container(
                      height: 90,
                      color: const Color(0xFF111111),
                      alignment: Alignment.center,
                      child: const Text('Loading ad...', style: TextStyle(color: Colors.white38)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}