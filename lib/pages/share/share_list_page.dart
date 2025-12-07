// lib/pages/share/share_list_page.dart
// FINAL — SHARED LIST VIEWER — DEEP LINK READY — ZERO ERRORS — BEAUTIFUL

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShareListPage extends StatefulWidget {
  final String shareId;
  const ShareListPage({super.key, required this.shareId});

  @override
  State<ShareListPage> createState() => _ShareListPageState();
}

class _ShareListPageState extends State<ShareListPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> items = [];
  bool isLoading = true;
  bool notFound = false;

  @override
  void initState() {
    super.initState();
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
        items = List<Map<String, dynamic>>.from(response['shopping_list_items']);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
        notFound = true;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Shared Shopping List', style: TextStyle(color: Colors.cyan)),
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
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text(
                        'Someone shared a list with you!',
                        style: TextStyle(fontSize: 20, color: Colors.cyan, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),

                      Expanded(
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final item = items[i];
                            final checked = item['is_checked'] as bool? ?? false;
                            final name = item['name'] as String? ?? 'Item';
                            final qty = item['quantity'] as int? ?? 1;
                            final price = (item['price'] as num?)?.toDouble() ?? 0.0;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
                              child: Row(
                                children: [
                                  Icon(
                                    checked ? Icons.check_box : Icons.check_box_outline_blank,
                                    color: checked ? Colors.white54 : Colors.white70,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: checked ? Colors.white54 : Colors.white,
                                        decoration: checked ? TextDecoration.lineThrough : null,
                                      ),
                                    ),
                                  ),
                                  Text('×$qty', style: const TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 12),
                                  Text('R${(price * qty).toStringAsFixed(0)}', style: const TextStyle(color: Colors.cyan, fontSize: 18, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(vertical: 20),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Grand Total', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                            Text('R${total.toStringAsFixed(0)}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.cyan)),
                          ],
                        ),
                      ),

                      const Text(
                        'Download List Easy to create your own lists!',
                        style: TextStyle(color: Colors.white54),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }
}