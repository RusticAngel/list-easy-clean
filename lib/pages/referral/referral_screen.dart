// lib/pages/referral/referral_screen.dart
// FINAL VERSION WITH ALL TIERS + BANNER AD + SMALLER TEXT
// + Consistent "Loading ad..." placeholder (matches other pages)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});
  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final supabase = Supabase.instance.client;

  String referralCode = 'LOADING...';
  String referralLink = '';
  int totalReferrals = 0;
  int freeMonths = 0;

  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadBannerAd();
  }

  Future<void> _loadData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final code = user.userMetadata?['referral_code'] ??
        user.id.substring(0, 8).toUpperCase();
    final link =
        'https://play.google.com/store/apps/details?id=com.rusticangel.list_easy&referral=$code';

    final refs =
        await supabase.from('referrals').select().eq('referrer_id', user.id);
    final count = refs.length;

    if (mounted) {
      setState(() {
        referralCode = code;
        referralLink = link;
        totalReferrals = count;
        freeMonths = (count / 2).floor();
      });
    }
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-1957460965962453/8166692213',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdReady = true),
        onAdFailedToLoad: (ad, err) => ad.dispose(),
      ),
    )..load();
  }

  void _shareReferral() {
    final message = '''
I’m loving List Easy — the smartest grocery app ever!

It learns what I buy and puts it at the top of the list. Saves me so much time.

Download free and get your first month premium FREE with my code:

$referralLink

We both get free premium months when you sign up and finish a shopping adventure!
    '''
        .trim();

    Share.share(message, subject: 'Join me on List Easy!');
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
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
        title: const Text('Referral Program',
            style: TextStyle(color: Colors.white, fontSize: 20)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Your Stats
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text('Your Referral Stats',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statItem('$totalReferrals', 'Total Referrals'),
                      _statItem('$freeMonths', 'Free Months Earned'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  LinearProgressIndicator(
                    value: (totalReferrals % 2) / 2,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${2 - (totalReferrals % 2)} more needed for next free month',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Referral Link + Share Buttons
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Share Your Link',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(
                            referralLink,
                            style: const TextStyle(
                                color: Colors.cyan, fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Colors.white70),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: referralLink));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied!')),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _shareReferral,
                      icon: const Icon(Icons.share, size: 28),
                      label: const Text('Share with Friends',
                          style: TextStyle(fontSize: 18)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // How It Works
            const Text('How It Works',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 20),
            _howItWorksItem('1', 'Share your unique link',
                'Send it to friends, family, or on social media'),
            _howItWorksItem('2', 'They sign up & use the app',
                'They must create at least one list'),
            _howItWorksItem('3', 'You both get rewarded',
                'Every 2 successful referrals = 1 free premium month'),

            const SizedBox(height: 40),

            // Reward Tiers — with Diamond + Legend + smaller text
            const Text('Reward Tiers',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 20),
            _tierCard('Bronze', '10 referrals', '1 month free'),
            _tierCard('Silver', '20 referrals', '3 months free'),
            _tierCard('Gold', '30 referrals', '6 months free'),
            _tierCard('Platinum', '40 referrals', '9 months free'),
            _tierCard('Diamond', '50 referrals', '12 months free'),
            _tierCard('Legend', '100 referrals', 'Lifetime free',
                isSpecial: true),

            const SizedBox(height: 40),

            // Banner Ad at Bottom (with consistent placeholder)
            if (_isBannerAdReady)
              Container(
                height: _bannerAd!.size.height.toDouble(),
                width: double.infinity,
                alignment: Alignment.center,
                child: AdWidget(ad: _bannerAd!),
              )
            else
              Container(
                height: 90,
                color: const Color(0xFF111111),
                alignment: Alignment.center,
                child: const Text(
                  'Loading ad...',
                  style: TextStyle(color: Colors.white38),
                ),
              ),

            const SizedBox(height: 100), // Extra space at bottom
          ],
        ),
      ),
    );
  }

  Widget _statItem(String value, String label) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.cyan)),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      );

  Widget _howItWorksItem(String number, String title, String subtitle) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.cyan,
              child: Text(number,
                  style: const TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _tierCard(String tier, String needed, String reward,
          {bool isSpecial = false}) =>
      Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSpecial ? const Color(0xFF6A1B9A) : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: isSpecial
              ? Border.all(color: Colors.purpleAccent, width: 2)
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(tier,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isSpecial ? Colors.white : Colors.cyan)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(reward,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.greenAccent)), // Smaller text
                Text(needed,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)), // Smaller text
              ],
            ),
          ],
        ),
      );
}
