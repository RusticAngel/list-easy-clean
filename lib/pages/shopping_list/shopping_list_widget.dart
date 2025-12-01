import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../supabase.dart';  // Adjust if needed

class ShoppingListWidget extends StatefulWidget {
  final String listId;
  const ShoppingListWidget({super.key, required this.listId});

  static const routeName = 'ShoppingList';

  @override
  State<ShoppingListWidget> createState() => _ShoppingListWidgetState();
}

class _ShoppingListWidgetState extends State<ShoppingListWidget> {
  double total = 0.0;
  BannerAd? _bannerAd;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',  // TEST ID - replace with real
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => setState(() {}),
      ),
    );
    _bannerAd!.load();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: Scaffold(
        backgroundColor: const Color(0xFF000409),
        appBar: AppBar(
          backgroundColor: Colors.black,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20.0),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Your Shopping List',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: IconButton(
                icon: const Icon(Icons.share, color: Colors.white, size: 20.0),
                onPressed: () {
                  // Add sharing logic later
                },
              ),
            ),
          ],
          centerTitle: true,
          elevation: 0.0,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: supabase
                      .from('shopping_list_items')
                      .stream(primaryKey: ['id'])
                      .eq('list_id', widget.listId)
                      .order('is_checked', ascending: true),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = snapshot.data!;
                    total = items.fold(0.0, (sum, item) => sum + (item['quantity'] as double? ?? 1) * (item['price'] as double? ?? 0));

                    return ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isChecked = item['is_checked'] as bool? ?? false;

                        return ListTile(
                          leading: Checkbox(
                            value: isChecked,
                            activeColor: Colors.white,
                            checkColor: Colors.black,
                            onChanged: (val) async {
                              await supabase.from('shopping_list_items').update({'is_checked': val}).eq('id', item['id']);
                            },
                          ),
                          title: Text(
                            item['item_name'] as String,
                            style: TextStyle(
                              color: Colors.white,
                              decoration: isChecked ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 50,
                                child: TextField(
                                  controller: TextEditingController(text: (item['quantity'] as double? ?? 1).toString()),
                                  onChanged: (val) async {
                                    await supabase.from('shopping_list_items').update({'quantity': double.tryParse(val) ?? 1}).eq('id', item['id']);
                                    setState(() {});
                                  },
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 50,
                                child: TextField(
                                  controller: TextEditingController(text: (item['price'] as double? ?? 0).toString()),
                                  onChanged: (val) async {
                                    await supabase.from('shopping_list_items').update({'price': double.tryParse(val) ?? 0}).eq('id', item['id']);
                                    setState(() {});
                                  },
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Grand Total: R${total.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  // Finish logic - add if needed
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Finish', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (_bannerAd != null)
                SizedBox(
                  height: _bannerAd!.size.height.toDouble(),
                  width: _bannerAd!.size.width.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }
}