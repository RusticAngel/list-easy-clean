// lib/pages/referral_page/referral_page_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';

final supabase = Supabase.instance.client;

class ReferralWidget extends StatefulWidget {
  const ReferralWidget({super.key});

  @override
  State<ReferralWidget> createState() => _ReferralWidgetState();
}

class _ReferralWidgetState extends State<ReferralWidget> {
  late final Future<Map<String, dynamic>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<Map<String, dynamic>> _loadData() async {
    final userId = supabase.auth.currentUser!.id;

    final res = await supabase
        .from('referral_codes')
        .select('code')
        .eq('user_id', userId)
        .maybeSingle();

    late String code;
    if (res == null) {
      code = userId.substring(0, 8).toUpperCase();
      await supabase.from('referral_codes').insert({'user_id': userId, 'code': code});
    } else {
      code = res['code'] as String;
    }

    final countRes = await supabase
        .from('users')
        .select('id')
        .eq('referred_by', code)
        .count();

    final int referrals = countRes.count;
    final int freeMonths = (referrals / 2).floor();
    final double progress = (referrals % 2) / 2.0;
    final int needed = 2 - (referrals % 2);

    return {
      'code': code,
      'referrals': referrals,
      'freeMonths': freeMonths,
      'progress': progress,
      'needed': needed,
      'link': 'https://your-app.com/signup?ref=$code',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000409),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text('Referral Program', style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Error loading data', style: TextStyle(color: Colors.white)));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Colors.cyan));
          }

          final data = snapshot.data!;
          final link = data['link'] as String;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _card(
                  child: Column(
                    children: [
                      const Text('Your Referral Link', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 12),
                      SelectableText(link, style: const TextStyle(color: Colors.cyan, fontFamily: 'monospace', fontSize: 16)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: link));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied!')));
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy'),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            // FIXED: no more deprecation warnings
                            onPressed: () async {
                              await SharePlus.instance.share(
                                text: 'Join List Easy and get premium features! $link',
                                subject: 'Join List Easy!',
                              );
                            },
                            icon: const Icon(Icons.share),
                            label: const Text('Share'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // ... rest of your UI
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: const Color(0xFF1C1C1A), borderRadius: BorderRadius.circular(16)),
        child: child,
      );
}