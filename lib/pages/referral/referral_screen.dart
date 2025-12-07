// lib/pages/referral/referral_screen.dart
// FINAL LAUNCH VERSION — NATIVE WHATSAPP + FACEBOOK DIRECT SHARE

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});
  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final supabase = Supabase.instance.client;

  String referralCode = 'LOADING';
  String referralLink = 'Loading...';
  int totalReferrals = 0;
  int freeMonths = 0;
  List<Map<String, dynamic>> leaderboard = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final code = user.userMetadata?['referral_code'] ?? user.id.substring(0, 8).toUpperCase();
    final link = 'https://play.google.com/store/apps/details?id=com.yourname.listeasy&referral=$code';

    final refs = await supabase.from('referrals').select().eq('referrer_id', user.id);
    final count = refs.length;

    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final boardData = await supabase
        .from('referrals')
        .select('referrer_id')
        .gte('created_at', firstDay.toIso8601String());

    final scores = <String, int>{};
    for (var r in boardData) {
      final id = r['referrer_id'] as String;
      scores[id] = (scores[id] ?? 0) + 1;
    }
    final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top10 = sorted.take(10).toList();

    final topUsers = <Map<String, dynamic>>[];
    for (var e in top10) {
      final profile = await supabase.from('profiles').select('username').eq('id', e.key).maybeSingle();
      topUsers.add({
        'username': profile?['username'] ?? 'User${e.key.substring(0, 6)}',
        'count': e.value,
      });
    }

    if (mounted) {
      setState(() {
        referralCode = code;
        referralLink = link;
        totalReferrals = count;
        freeMonths = (count / 2).floor();
        leaderboard = topUsers;
      });
    }
  }

  // DIRECT SHARE — OPENS WHATSAPP/FACEBOOK NATIVE APP
  Future<void> _shareViaApp(String platform) async {
    final message = '''
I just saved R287 on groceries with List Easy — the smartest shopping app in SA!

It learns what I buy every week and shows it first.

Download free and get your first month premium FREE with my code:

$referralLink

Use my referral and we both get free premium months!
    '''.trim();

    String url = '';
    if (platform == 'whatsapp') {
      url = 'whatsapp://send?text=${Uri.encodeComponent(message)}';
    } else if (platform == 'facebook') {
      url = 'fb://facewebmodal/f?href=${Uri.encodeComponent(referralLink)}';
    }

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      // Fallback to system share
      await Share.share(message, subject: 'Join me on List Easy!');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => context.pop()),
        title: const Text('Referral Program', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Your Stats (unchanged)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  const Text('Your Stats', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statColumn(totalReferrals.toString(), 'Total Referrals'),
                      _statColumn(freeMonths.toString(), 'Free Months Earned'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: (totalReferrals % 2) / 2,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.cyan),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${2 - (totalReferrals % 2)} more referrals needed',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Invite Friends — NOW WITH NATIVE SHARE BUTTONS
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Invite Friends', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 12),
                  const Text('Referral Link', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
                          child: SelectableText(referralLink, style: const TextStyle(color: Colors.cyan)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.white70),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: referralLink));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied!')));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Share via', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 16),

                  // WHATSAPP — OPENS NATIVE APP
                  ElevatedButton.icon(
                    onPressed: () => _shareViaApp('whatsapp'),
                    icon: Image.asset('assets/whatsapp_logo.jpg', height: 28),
                    label: const Text('Share on WhatsApp', style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // FACEBOOK — OPENS NATIVE APP
                  ElevatedButton.icon(
                    onPressed: () => _shareViaApp('facebook'),
                    icon: Image.asset('assets/facebook_logo.png', height: 28),
                    label: const Text('Share on Facebook', style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1877F2),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                  ),
                ],
              ),
            ),

            // Rest of your screen (How it Works, Leaderboard, etc.) unchanged
            const SizedBox(height: 24),
            // ... keep your existing How it Works + Leaderboard sections ...
          ],
        ),
      ),
    );
  }

  // Keep your existing helper widgets (_statColumn, _tierBox, etc.) unchanged
  Widget _statColumn(String value, String label) => Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      );

  // ... rest of your helper widgets (tierBox, howItWorksStep, etc.) unchanged ...
}