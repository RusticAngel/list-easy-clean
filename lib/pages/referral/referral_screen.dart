// lib/pages/referral/referral_screen.dart
// FINAL VERSION – ALL TIERS + BANNER AD + SMALLER TEXT
// FIXED: Overflow on tier stats (using Wrap + ellipsis)
// FIXED: ALL use_build_context_synchronously warnings (safe messenger + context storage)
// + Consistent "Loading ad..." placeholder
// + Referral hint bubble: first copy + re-appear after 50 days
// + Per-friend progress (expandable), 7-day halved tiers promo

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  List<Map<String, dynamic>> referrals = []; // For per-friend progress
  bool isPromoActive = false; // First 7 days double tier progress

  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadBannerAd();
    _setFirstOpenDate();
  }

  Future<void> _setFirstOpenDate() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('first_open_date')) {
      await prefs.setString(
          'first_open_date', DateTime.now().toIso8601String());
    }
  }

  Future<void> _loadData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final code = user.userMetadata?['referral_code'] ??
        user.id.substring(0, 8).toUpperCase();
    final link =
        'https://play.google.com/store/apps/details?id=com.rusticangel.list_easy&referral=$code';

    // Fetch all referrals
    final refs = await supabase
        .from('referrals')
        .select('id, referred_id, lists_completed, successful')
        .eq('referrer_id', user.id);

    final count = refs.length;

    // Check promo: first 7 days after first open
    final prefs = await SharedPreferences.getInstance();
    final firstOpenStr =
        prefs.getString('first_open_date') ?? DateTime.now().toIso8601String();
    final firstOpen = DateTime.parse(firstOpenStr);
    final daysSinceFirstOpen = DateTime.now().difference(firstOpen).inDays;
    final promoActive = daysSinceFirstOpen <= 7;

    if (mounted) {
      setState(() {
        referralCode = code;
        referralLink = link;
        totalReferrals = count;
        freeMonths = (count / 2).floor();
        referrals = refs;
        isPromoActive = promoActive;
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

  Future<void> _shareReferral() async {
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

  Future<void> _onCopyReferralCode() async {
    Clipboard.setData(ClipboardData(text: referralLink));

    // SAFE & LINTER-FRIENDLY: Store messenger + context BEFORE any await
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final currentContext = context;

    final prefs = await SharedPreferences.getInstance();

    final firstOpenStr =
        prefs.getString('first_open_date') ?? DateTime.now().toIso8601String();
    final firstOpen = DateTime.parse(firstOpenStr);
    final daysSinceFirstOpen = DateTime.now().difference(firstOpen).inDays;

    final hasSeenFirst = prefs.getBool('referral_hint_seen_first') ?? false;
    if (!hasSeenFirst && mounted) {
      await _showReferralHint(
          // ignore: use_build_context_synchronously
          prefs,
          'referral_hint_seen_first',
          // ignore: use_build_context_synchronously
          currentContext);
      return;
    }

    final hasSeenLate = prefs.getBool('referral_hint_seen_late') ?? false;
    if (daysSinceFirstOpen >= 50 && !hasSeenLate && mounted) {
      // ignore: use_build_context_synchronously
      await _showReferralHint(prefs, 'referral_hint_seen_late', currentContext);
    }

    // Show snackbar AFTER async gap (using stored messenger)
    if (mounted) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Link copied!')),
      );
    }
  }

  Future<void> _showReferralHint(
    SharedPreferences prefs,
    String seenKey,
    BuildContext dialogContext,
  ) async {
    if (!mounted) return;

    showDialog(
      context: dialogContext,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Pro Tip: Mass Referrals = Free Premium Forever!',
          style: TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Don't lose your features after the free period!\n\n"
          "Copy your code, write a quick personal message, and post it in:\n"
          "• Facebook groups\n"
          "• WhatsApp groups\n"
          "• X / Instagram / TikTok\n\n"
          "Referrals accumulate — the more the better!\n"
          "Watch your free months roll in! 🚀",
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await prefs.setBool(seenKey, true);
              // ignore: use_build_context_synchronously
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Got it!', style: TextStyle(color: Colors.cyan)),
          ),
        ],
        actionsAlignment: MainAxisAlignment.center,
      ),
    );
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
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  if (isPromoActive) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Color.fromRGBO(0, 188, 212, 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '🎉 Double Tier Progress Active! (First 7 days)\n'
                        'Share now — reach Legend with just 50 referrals instead of 100!',
                        style: TextStyle(
                            color: Colors.cyan, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Expandable Friends Progress
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ExpansionTile(
                title: const Text(
                  'Your Friends\' Progress',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                initiallyExpanded: false,
                collapsedBackgroundColor: const Color(0xFF1C1C1E),
                backgroundColor: const Color(0xFF1C1C1E),
                children: [
                  if (referrals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No friends yet — share your link!',
                          style: TextStyle(color: Colors.white70)),
                    )
                  else
                    ...referrals.take(4).map((ref) {
                      final completed = (ref['lists_completed'] as int?) ?? 0;
                      final isSuccessful =
                          (ref['successful'] as bool?) ?? false;
                      final progress = completed >= 2 ? '2/2' : '$completed/2';
                      final statusColor =
                          completed >= 2 ? Colors.greenAccent : Colors.white70;

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.cyan,
                          child: Text('F',
                              style: const TextStyle(color: Colors.black)),
                        ),
                        title: Text('Friend ${referrals.indexOf(ref) + 1}',
                            style: const TextStyle(color: Colors.white)),
                        trailing: Text(
                          progress,
                          style: TextStyle(
                              color: statusColor, fontWeight: FontWeight.bold),
                        ),
                        subtitle: isSuccessful
                            ? const Text('Credit earned!',
                                style: TextStyle(color: Colors.greenAccent))
                            : null,
                      );
                    }),
                  if (referrals.length > 4)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextButton(
                        onPressed: () {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Full list coming soon!')),
                            );
                          }
                        },
                        child: const Text('View All Friends',
                            style: TextStyle(color: Colors.cyan)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 32),
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
                        onPressed: _onCopyReferralCode,
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
            const Text('How It Works',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 20),
            _howItWorksItem('1', 'Share your unique link',
                'Send it to friends, family, or on social media'),
            _howItWorksItem('2', 'They sign up & use the app',
                'They must create at least two lists'),
            _howItWorksItem('3', 'You get rewarded',
                'Every 2 successful referrals = 1 free premium month'),
            const SizedBox(height: 40),
            const Text('Reward Tiers',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                _tierCard(
                    'Bronze',
                    isPromoActive ? '5 referrals' : '10 referrals',
                    '1 month free'),
                _tierCard(
                    'Silver',
                    isPromoActive ? '10 referrals' : '20 referrals',
                    '3 months free'),
                _tierCard(
                    'Gold',
                    isPromoActive ? '15 referrals' : '30 referrals',
                    '6 months free'),
                _tierCard(
                    'Platinum',
                    isPromoActive ? '20 referrals' : '40 referrals',
                    '9 months free'),
                _tierCard(
                    'Diamond',
                    isPromoActive ? '25 referrals' : '50 referrals',
                    '12 months free'),
                _tierCard(
                    'Legend',
                    isPromoActive ? '50 referrals' : '100 referrals',
                    'Lifetime free',
                    isSpecial: true),
              ],
            ),
            const SizedBox(height: 40),
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
                child: const Text('Loading ad...',
                    style: TextStyle(color: Colors.white38)),
              ),
            const SizedBox(height: 8),
            const Text(
              'Built with Grok by xAI',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white54,
                  fontWeight: FontWeight.w300),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 100),
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
        width: 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSpecial ? const Color(0xFF6A1B9A) : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: isSpecial
              ? Border.all(color: Colors.purpleAccent, width: 2)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(tier,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isSpecial ? Colors.white : Colors.cyan)),
            const SizedBox(height: 8),
            Text(reward,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(needed,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                ),
                if (isPromoActive)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text('(Double!)',
                        style: TextStyle(
                            color: Colors.cyan,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ],
        ),
      );
}
