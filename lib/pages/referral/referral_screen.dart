// lib/pages/referral/referral_screen.dart
// FINAL VERSION – ALL TIERS + REFERRAL CLARIFICATION TEXT
// Banner ads disabled for clean v1.0 launch (low fill rate on new app)
// Re-enable when traffic grows and ads are reliable
// Added: Short "rewards are extra / added on top" bullet under "How it works"

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  String referralCode = 'LOADING...';
  String referralLink = '';
  int totalReferrals = 0;
  int freeMonths = 0;
  List<Map<String, dynamic>> referrals = [];
  bool isPromoActive = false;

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _loadData();
    _setFirstOpenDate();

    // NEW: Check for hint on first open + 50-day re-trigger
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showReferralHintIfNeeded();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
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

    final refs = await supabase
        .from('referrals')
        .select('id, referred_id, lists_completed, successful')
        .eq('referrer_id', user.id);

    final count = refs.length;

    final prefs = await SharedPreferences.getInstance();
    final firstOpenStr =
        prefs.getString('first_open_date') ?? DateTime.now().toIso8601String();
    final firstOpen = DateTime.parse(firstOpenStr);
    final daysSinceFirstOpen = DateTime.now().difference(firstOpen).inDays;

    final promoActive = daysSinceFirstOpen >= 16 && daysSinceFirstOpen <= 22;

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

  Future<void> _shareReferral() async {
    _animController.forward().then((_) => _animController.reverse());

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
    _animController.forward().then((_) => _animController.reverse());

    Clipboard.setData(ClipboardData(text: referralLink));

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (mounted) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Link copied!')),
      );
    }
  }

  // NEW: Trigger hint on first open of referral page + re-trigger after 50 days
  Future<void> _showReferralHintIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenFirst =
        prefs.getBool('referral_page_hint_seen_first') ?? false;
    final hasSeenLate = prefs.getBool('referral_page_hint_seen_late') ?? false;

    final firstOpenStr =
        prefs.getString('first_open_date') ?? DateTime.now().toIso8601String();
    final firstOpen = DateTime.parse(firstOpenStr);
    final daysSinceFirstOpen = DateTime.now().difference(firstOpen).inDays;

    if (!hasSeenFirst) {
      // ignore: use_build_context_synchronously
      await _showReferralHint(prefs, 'referral_page_hint_seen_first', context);
    } else if (daysSinceFirstOpen >= 50 && !hasSeenLate) {
      // ignore: use_build_context_synchronously
      await _showReferralHint(prefs, 'referral_page_hint_seen_late', context);
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
          style: TextStyle(
              color: Colors.cyan, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        content: SingleChildScrollView(
          child: const Text(
            "Don't lose your features after the free period!\n\n"
            "Copy your code, write a quick personal message, and post it in:\n"
            "• Facebook groups\n"
            "• WhatsApp groups\n"
            "• X / Instagram / TikTok\n\n"
            "Referrals accumulate — the more the better!\n"
            "Watch your free months roll in! 🚀",
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
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

  void _showAllFriends() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('All Friends\' Progress',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: referrals.isEmpty
              ? const Center(
                  child: Text('No friends yet',
                      style: TextStyle(color: Colors.white70)))
              : ListView.builder(
                  itemCount: referrals.length,
                  itemBuilder: (context, index) {
                    final ref = referrals[index];
                    final completed = (ref['lists_completed'] as int?) ?? 0;
                    final isSuccessful = (ref['successful'] as bool?) ?? false;
                    final progress = completed >= 2 ? '2/2' : '$completed/2';
                    final statusColor =
                        completed >= 2 ? Colors.greenAccent : Colors.white70;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 0),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.cyan,
                        child: Text('F',
                            style: const TextStyle(color: Colors.black)),
                      ),
                      title: Text('Friend ${referrals.indexOf(ref) + 1}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                      trailing: Text(
                        progress,
                        style: TextStyle(
                            color: statusColor, fontWeight: FontWeight.bold),
                      ),
                      subtitle: isSuccessful
                          ? const Text('Credit earned!',
                              style: TextStyle(
                                  color: Colors.greenAccent, fontSize: 12))
                          : null,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.cyan)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('Referral Program',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text('Your Referral Stats',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statItem('$totalReferrals', 'Total Referrals'),
                      _statItem('$freeMonths', 'Free Months Earned'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Column(
                    children: [
                      LinearProgressIndicator(
                        value: (totalReferrals % 2) / 2,
                        backgroundColor: Colors.white24,
                        valueColor:
                            const AlwaysStoppedAnimation(Colors.white70),
                        minHeight: 8,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${2 - (totalReferrals % 2)} more needed for next free month',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  if (isPromoActive) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Color.fromRGBO(0, 188, 212, 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        '🎉 Double Tier Progress Active! (Days 16–22)\n'
                        'Share now — reach Legend with just 50 referrals instead of 100!',
                        style: TextStyle(
                            color: Colors.cyan,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExpansionTile(
                title: const Text(
                  'Your Friends\' Progress',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                initiallyExpanded: false,
                collapsedBackgroundColor: const Color(0xFF1C1C1E),
                backgroundColor: const Color(0xFF1C1C1E),
                children: [
                  if (referrals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No friends yet — share your link!',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 14)),
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
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 0),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.cyan,
                          child: Text('F',
                              style: const TextStyle(color: Colors.black)),
                        ),
                        title: Text('Friend ${referrals.indexOf(ref) + 1}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14)),
                        trailing: Text(
                          progress,
                          style: TextStyle(
                              color: statusColor, fontWeight: FontWeight.bold),
                        ),
                        subtitle: isSuccessful
                            ? const Text('Credit earned!',
                                style: TextStyle(
                                    color: Colors.greenAccent, fontSize: 12))
                            : null,
                      );
                    }),
                  if (referrals.length > 4)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextButton(
                        onPressed: _showAllFriends,
                        child: const Text('View All Friends',
                            style: TextStyle(color: Colors.cyan, fontSize: 14)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Share Your Link',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SelectableText(
                            referralLink,
                            style: const TextStyle(
                                color: Colors.cyan, fontSize: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: IconButton(
                          icon: const Icon(Icons.copy,
                              color: Colors.white70, size: 20),
                          onPressed: _onCopyReferralCode,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _shareReferral,
                        icon: const Icon(Icons.share, size: 22),
                        label: const Text('Share with Friends',
                            style: TextStyle(fontSize: 15)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('How It Works',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 16),
            _howItWorksItem('1', 'Share your unique link',
                'Send it to friends, family, or on social media'),
            _howItWorksItem('2', 'They sign up & use the app',
                'They must create at least two lists'),
            _howItWorksItem('3', 'You get rewarded',
                'Every 2 successful referrals = 1 free premium month'),
            // NEW: Short clarification that rewards are extra / added on top
            _howItWorksItem(
              '',
              'Rewards are extra',
              'Free months are additional — added on top of your current subscription time.',
            ),
            const SizedBox(height: 24),
            const Text('Reward Tiers',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.1,
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
            // Banner removed – clean launch look
            const SizedBox(height: 16),
            const Text(
              '',
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.white54,
                  fontWeight: FontWeight.w300),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String value, String label) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.cyan)),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      );

  Widget _howItWorksItem(String number, String title, String subtitle) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (number.isNotEmpty)
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.cyan,
                child: Text(number,
                    style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
            if (number.isNotEmpty) const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title.isNotEmpty)
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  if (title.isNotEmpty) const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          color: number.isEmpty
                              ? Colors.cyanAccent
                              : Colors.white70,
                          fontSize: 13,
                          fontStyle: number.isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _tierCard(String tier, String needed, String reward,
          {bool isSpecial = false}) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSpecial ? const Color(0xFF6A1B9A) : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(12),
          border: isSpecial
              ? Border.all(color: Colors.purpleAccent, width: 1.5)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tier,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isSpecial ? Colors.white : Colors.cyan)),
            const SizedBox(height: 6),
            Text(reward,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent)),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(needed,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                ),
                if (isPromoActive)
                  const Padding(
                    padding: EdgeInsets.only(left: 3),
                    child: Text('(Double!)',
                        style: TextStyle(
                            color: Colors.cyan,
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ],
        ),
      );
}
