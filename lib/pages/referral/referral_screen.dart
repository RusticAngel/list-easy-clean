// lib/pages/referral/referral_screen.dart
// FINAL + TIERS + LEADERBOARD + HOW IT WORKS

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // Tier config
  final Map<String, int> tiers = {
    'Bronze': 0,
    'Silver': 5,
    'Gold': 15,
    'Platinum': 30,
  };

  @override
  void initState() {
    super.initState();
    _loadEverything();
  }

  Future<void> _loadEverything() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final code = user.userMetadata?['referral_code'] ?? user.id.substring(0, 8).toUpperCase();
    final link = 'https://app.listeasy.com/ref/$code';

    final refs = await supabase.from('referrals').select().eq('referrer_id', user.id);
    final count = refs.length;

    // Leaderboard (top 10 this month)
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final leaderboardData = await supabase
        .from('referrals')
        .select('referrer_id')
        .gte('created_at', firstDay.toIso8601String())
        .order('created_at');

    final Map<String, int> scores = {};
    for (var r in leaderboardData) {
      final id = r['referrer_id'] as String;
      scores[id] = (scores[id] ?? 0) + 1;
    }
    final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top10 = sorted.take(10).toList();

    // Fetch usernames for leaderboard
    final topUsers = <Map<String, dynamic>>[];
    for (var entry in top10) {
      final userData = await supabase.from('profiles').select('username').eq('id', entry.key).maybeSingle();
      topUsers.add({
        'username': userData?['username'] ?? 'User${entry.key.substring(0, 6)}',
        'count': entry.value,
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

  String get currentTier {
    if (totalReferrals >= 30) return 'Platinum';
    if (totalReferrals >= 15) return 'Gold';
    if (totalReferrals >= 5) return 'Silver';
    return 'Bronze';
  }

  int get nextTierTarget {
    if (totalReferrals >= 30) return 999;
    if (totalReferrals >= 15) return 30;
    if (totalReferrals >= 5) return 15;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => context.pop()),
        title: const Text('Referral Program', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Your Code
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  const Text('Your Referral Code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: SelectableText(referralCode, style: const TextStyle(fontSize: 24, color: Colors.cyan, fontWeight: FontWeight.bold))),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.cyan),
                        onPressed: () => Clipboard.setData(ClipboardData(text: referralLink)).then((_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied!')))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => Share.share('Join List Easy with my code $referralCode and we both get free months!\n$referralLink'),
                    icon: const Icon(Icons.share, color: Colors.black),
                    label: const Text('Share Link', style: TextStyle(color: Colors.black)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Tier Progress
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Text('Your Tier: $currentTier', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.cyan)),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: totalReferrals / nextTierTarget,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation<Color>(currentTier == 'Platinum' ? Colors.purple : Colors.cyan),
                  ),
                  const SizedBox(height: 8),
                  Text('$totalReferrals / $nextTierTarget referrals', style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
                  Text('Every 2 referrals = 1 free month', style: const TextStyle(color: Colors.white60)),
                  Text('You have earned: $freeMonths free months', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Leaderboard
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('This Month\'s Top Referrers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  leaderboard.isEmpty
                      ? const Text('No referrals yet this month', style: TextStyle(color: Colors.white54))
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: leaderboard.length,
                          itemBuilder: (ctx, i) {
                            final entry = leaderboard[i];
                            return ListTile(
                              leading: CircleAvatar(backgroundColor: i < 3 ? Colors.amber : Colors.white24, child: Text('${i + 1}', style: const TextStyle(color: Colors.black))),
                              title: Text(entry['username'], style: const TextStyle(color: Colors.white)),
                              trailing: Text('${entry['count']} refs', style: const TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold)),
                            );
                          },
                        ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // How it works
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('How it Works', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Text('• Share your unique link with friends', style: TextStyle(color: Colors.white70)),
                  Text('• They sign up using your link', style: TextStyle(color: Colors.white70)),
                  Text('• You both climb the tiers', style: TextStyle(color: Colors.white70)),
                  Text('• Every 2 referrals = 1 free month', style: TextStyle(color: Colors.white70)),
                  Text('• Top 3 monthly get extra rewards', style: TextStyle(color: Colors.cyan)),
                ],
              ),
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}