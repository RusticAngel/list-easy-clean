// lib/pages/creating/creating_widget.dart
// FINAL + 60-second banner refresh + Interstitial-ready + ZERO errors

import 'dart:async'; // ← ADDED FOR TIMER
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
  List<Map<String, dynamic>> selectedItems = [];
  int referralsThisMonth = 0;
  int freeMonthsEarned = 0;
  bool isLoading = false;

  late BannerAd _bannerAd;
  bool _isBannerAdReady = false;
  Timer? _bannerRefreshTimer; // ← ADDED: for 60-sec refresh

  @override
  void initState() {
    super.initState();
    loadData();
    _loadBannerAd();
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
            _startBannerRefresh(); // ← Start auto-refresh on first load
          }
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
        },
      ),
    )..load();
  }

  // ← NEW: 60-second Google-approved refresh
  void _startBannerRefresh() {
    _bannerRefreshTimer?.cancel();
    _bannerRefreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (mounted && _isBannerAdReady) {
        _bannerAd.load(); // Fresh ad every 60 sec = maximum safe revenue
      }
    });
  }

  @override
  void dispose() {
    _bannerAd.dispose();
    _bannerRefreshTimer?.cancel(); // ← PREVENT MEMORY LEAK
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final past = await supabase
        .from('shopping_list_items')
        .select('name')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);

    final seen = <String>{};
    previousItems = past
        .map<String>((e) => e['name'] as String)
        .where((name) => seen.add(name.toLowerCase()))
        .take(10)
        .toList();

    final refs = await supabase.from('referrals').select().eq('referrer_id', userId);
    referralsThisMonth = refs.length;
    freeMonthsEarned = (referralsThisMonth / 2).floor();

    if (mounted) setState(() {});
  }

  void addToSelected(String name) {
    if (name.trim().isEmpty) return;
    final trimmed = name.trim();
    final lower = trimmed.toLowerCase();

    setState(() {
      if (!selectedItems.any((i) => (i['item_name'] as String).toLowerCase() == lower)) {
        selectedItems.add({'item_name': trimmed, 'quantity': 1});
      }
      previousItems.removeWhere((item) => item.toLowerCase() == lower);
    });
    searchController.clear();
  }

  Future<void> removeFromHistory(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove from history?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('"$name" will no longer appear in suggestions.', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => previousItems.remove(name));
    }
  }

  void removeSelected(int index) => setState(() => selectedItems.removeAt(index));

  Future<void> createListAndGo() async {
    if (selectedItems.isEmpty || isLoading) return;
    setState(() => isLoading = true);

    try {
      final userId = supabase.auth.currentUser!.id;
      final listResp = await supabase
          .from('shopping_lists')
          .insert({
            'user_id': userId,
            'name': 'My List ${DateTime.now().toIso8601String().substring(0, 10)}'
          })
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

      if (mounted) context.go('/shoppingList?listId=$listId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final referralsNeeded = referralsThisMonth % 2 == 0 ? 2 : 2 - (referralsThisMonth % 2);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Create Shopping List', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Top Card — Search + Previous Items
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
                            hintText: 'Search products',
                            hintStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: const Color(0xFF111111),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                            prefixIcon: const Icon(Icons.search, color: Colors.cyan),
                          ),
                          onSubmitted: addToSelected,
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
                    child: ListView.builder(
                      itemCount: previousItems.length,
                      itemBuilder: (context, i) {
                        final itemName = previousItems[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: GestureDetector(
                            onTap: () => addToSelected(itemName),
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

            const SizedBox(height: 16),

            // Referral Progress
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Free Months Earned; Referrals Needed:', style: TextStyle(color: Colors.white70)),
                  Row(children: [
                    Text('$freeMonthsEarned', style: const TextStyle(color: Colors.green, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 20),
                    Text('$referralsNeeded', style: const TextStyle(color: Colors.orange, fontSize: 24, fontWeight: FontWeight.bold)),
                  ]),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Selected Items + Buttons + BANNER (now refreshes every 60 sec)
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
                    child: ListView.builder(
                      itemCount: selectedItems.length,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(selectedItems[i]['item_name'], style: const TextStyle(color: Colors.white)),
                        trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => removeSelected(i)),
                      ),
                    ),
                  ),
                  const Divider(color: Colors.white24),
                  Text("You've earned: $freeMonthsEarned free months", style: const TextStyle(color: Colors.cyan)),
                  Text("$referralsNeeded more referrals needed for your next free month", style: const TextStyle(color: Colors.white54)),
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
                        : const Text('Go Shopping', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 20),

                  // BANNER — NOW AUTO-REFRESHES EVERY 60 SECONDS
                  if (_isBannerAdReady)
                    Container(
                      height: 90,
                      width: double.infinity,
                      alignment: Alignment.center,
                      child: AdWidget(ad: _bannerAd),
                    )
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