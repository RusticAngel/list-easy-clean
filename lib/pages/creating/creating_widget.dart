// lib/pages/creating/creating_widget.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Load previous items (last 10 unique)
    final past = await supabase
        .from('list_items')
        .select('item_name')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);

    final unique = <String>{};
    previousItems = past
        .map<String>((e) => e['item_name'] as String)
        .where((name) => unique.add(name))
        .take(10)
        .toList();

    // Load referral count
    final refs = await supabase
        .from('referrals')
        .select()
        .eq('referrer_id', userId);

    referralsThisMonth = refs.length;
    freeMonthsEarned = (referralsThisMonth / 2).floor();

    if (mounted) setState(() {});
  }

  void addToSelected(String name) {
    if (name.trim().isEmpty) return;
    setState(() {
      selectedItems.add({'item_name': name.trim(), 'quantity': 1});
    });
    searchController.clear();
  }

  void removeSelected(int index) {
    setState(() {
      selectedItems.removeAt(index);
    });
  }

  Future<void> createListAndGo() async {
    if (selectedItems.isEmpty) return;

    final userId = supabase.auth.currentUser!.id;

    final listResp = await supabase
        .from('shopping_lists')
        .insert({'user_id': userId, 'name': 'My List ${DateTime.now().toIso8601String().substring(0, 10)}'})
        .select()
        .single();

    final listId = listResp['id'];

    await supabase.from('list_items').insert(
      selectedItems.map((i) => {
            'list_id': listId,
            'item_name': i['item_name'],
            'user_id': userId,
            'quantity': i['quantity'],
          }),
    );

    if (mounted) context.go('/shoppingList?listId=$listId');
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
            // Top Card
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
                      itemBuilder: (c, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: GestureDetector(
                          onTap: () => addToSelected(previousItems[i]),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(color: const Color(0xFF222222), borderRadius: BorderRadius.circular(30)),
                            child: Text(previousItems[i], style: const TextStyle(color: Colors.white70)),
                          ),
                        ),
                      ),
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

            // Bottom Card
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
                      itemBuilder: (c, i) => ListTile(
                        title: Text(selectedItems[i]['item_name'], style: const TextStyle(color: Colors.white)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => removeSelected(i),
                        ),
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
                    onPressed: createListAndGo,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, shape: const StadiumBorder()),
                    child: const Text('Go Shopping', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 20),
                  Container(height: 90, color: const Color(0xFF111111), child: const Center(child: Text('Ad Banner Placeholder', style: TextStyle(color: Colors.white38)))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}