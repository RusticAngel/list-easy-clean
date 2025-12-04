// lib/pages/referral/referral_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart' as share_plus;  // ← this kills the deprecation warning
import 'package:supabase_flutter/supabase_flutter.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});
  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final supabase = Supabase.instance.client;

  int totalReferrals = 0;
  int freeMonths = 0;
  int referralsNeeded = 2;
  String referralLink = 'Loading...';
  String referralCode = 'LOADING';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final refs = await supabase.from('referrals').select().eq('referrer_id', user.id);
    final count = refs.length;
    final earned = (count / 2).floor();
    final needed = count % 2 == 0 ? 2 : 2 - (count % 2);
    final code = user.userMetadata?['referral_code'] ?? user.id.substring(0, 8).toUpperCase();
    final link = 'https://app.listeasy.com/ref/$code';

    if (mounted) {
      setState(() {
        totalReferrals = count;
        freeMonths = earned;
        referralsNeeded = needed;
        referralLink = link;
        referralCode = code;
      });
    }
  }

  Future<void> _share() async {
    await share_plus.Share.share(
      'Hey! Join List Easy and get your shopping organized — plus we both get free months!\n\n'
      'Referral link: $referralLink\n'
      'Code: $referralCode',
      subject: 'Join me on List Easy!',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text('Referral Program', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.white),
            onPressed: _share,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                const Text('Your Stats', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _stat('$totalReferrals', 'Total Referrals'),
                  _stat('$freeMonths', 'Free Months Earned'),
                ]),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: (totalReferrals % 2) / 2,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyan),
                ),
                const SizedBox(height: 8),
                Text('$referralsNeeded more referrals needed', style: const TextStyle(color: Colors.white70)),
              ]),
            ),

            const SizedBox(height: 24),

            // Invite Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Invite Friends', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
                      child: SelectableText(referralLink, style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.white70),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: referralLink));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied!')));
                    },
                  ),
                ]),
                const SizedBox(height: 16),
                const Text('Share via', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _shareBtn('assets/images/whatsapp.png'),
                  _shareBtn('assets/images/email.png'),
                  _shareBtn('assets/images/facebook.png'),
                  _shareBtn('assets/images/more.png'),
                ]),
              ]),
            ),

            const SizedBox(height: 40),
            const Center(child: Text('Ad Banner Placeholder', style: TextStyle(color: Colors.white38))),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) => Column(children: [
        Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ]);

  Widget _shareBtn(String asset) => GestureDetector(
        onTap: _share,
        child: Column(children: [
          Container(
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF333333), borderRadius: BorderRadius.circular(12)),
            child: Image.asset(asset, fit: BoxFit.contain),
          ),
          const SizedBox(height: 8),
          const Text('Share', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      );
}