import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core.dart';
import 'screens/sports.dart';
import 'screens/store.dart';
import 'screens/club.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: brandCream,
    ),
  );
  runApp(const NasconApp());
}

class NasconApp extends StatelessWidget {
  const NasconApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NaSCon Sports',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: const SplashScreen(),
  );
}

class SportsArtwork extends StatelessWidget {
  const SportsArtwork({super.key, this.size = 280});
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/sports-mascot.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel:
        'Football player in a green kit with a trophy and sports balls',
  );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashState();
}

class _SplashState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat(reverse: true);
  String? startupError;
  Future<void> boot() async {
    try {
      await Future.wait([
        app.init(),
        Future<void>.delayed(const Duration(milliseconds: 2200)),
      ]);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                app.loggedIn ? const HomeShell() : const LoginScreen(),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => startupError = 'Could not open saved data. Please try again.',
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => boot());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: controller,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(
                      0,
                      reduce ? 0 : math.sin(controller.value * math.pi) * -12,
                    ),
                    child: Transform.rotate(
                      angle: reduce
                          ? 0
                          : math.sin(controller.value * math.pi) * .025,
                      child: child,
                    ),
                  ),
                  child: const SportsArtwork(size: 300),
                ),
                const SizedBox(height: 30),
                const Text(
                  'NaSCon.',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                    color: brandInk,
                    letterSpacing: -2,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Every sport. One team.',
                  style: TextStyle(fontSize: 16, color: brandInk),
                ),
                const SizedBox(height: 42),
                if (startupError != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(startupError!, textAlign: TextAlign.center),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => startupError = null);
                      boot();
                    },
                    child: const Text('Try again'),
                  ),
                ] else
                  const SizedBox(
                    width: 76,
                    child: LinearProgressIndicator(
                      color: brandGreen,
                      backgroundColor: Color(0xffe1e8d4),
                      minHeight: 4,
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData roleIcon(String role) => switch (role) {
  'super_admin' => Icons.admin_panel_settings_outlined,
  'league_organizer' => Icons.emoji_events_outlined,
  'club_manager' => Icons.groups_outlined,
  'player' => Icons.sports_soccer,
  _ => Icons.person_outline,
};

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(), password = TextEditingController();
  bool obscure = true, remember = true, busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    final result = await app.login(
      email.text,
      password.text,
      remember: remember,
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (result) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeShell()),
      );
    } else {
      setState(
        () => error = 'Email or password does not match a demo account. Choose an account below to try again.',
      );
    }
  }

  void accounts() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose your demo account',
                style: Theme.of(c).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text(
                'All accounts use Nascon@26. Data stays on this device.',
              ),
              const SizedBox(height: 12),
              for (final e in demoRoles.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: brandCream,
                    child: Icon(roleIcon(e.key), color: brandInk),
                  ),
                  title: Text(e.value),
                  subtitle: Text(demoEmails[e.key]!),
                  trailing: const Icon(Icons.arrow_forward_rounded),
                  onTap: () {
                    email.text = demoEmails[e.key]!;
                    password.text = 'Nascon@26';
                    Navigator.pop(c);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: c.maxHeight < 650 ? 210 : 260,
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(
                      gradient: brandGradient,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(38),
                      ),
                    ),
                    child: Stack(
                      children: [
                        const Positioned(
                          left: 24,
                          top: 34,
                          child: Text(
                            'NaSCon.',
                            style: TextStyle(
                              fontSize: 31,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                        const Positioned(
                          left: 24,
                          top: 82,
                          child: SizedBox(
                            width: 145,
                            child: Text(
                              'Your club.\nYour game.\nYour moment.',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: -18,
                          bottom: -22,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(110),
                            child: SportsArtwork(
                              size: c.maxHeight < 650 ? 208 : 248,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Welcome back',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'A little closer to your next big win.',
                            style: TextStyle(color: Color(0xff637151)),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email address',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: (v) => v == null || !v.contains('@')
                                ? 'Enter a valid email address'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: password,
                            obscureText: obscure,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                tooltip: obscure
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () =>
                                    setState(() => obscure = !obscure),
                                icon: Icon(
                                  obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            validator: (v) => v == null || v.isEmpty
                                ? 'Enter your password'
                                : null,
                            onFieldSubmitted: (_) => login(),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          Row(
                            children: [
                              Checkbox(
                                value: remember,
                                onChanged: (v) => setState(() => remember = v!),
                              ),
                              const Expanded(
                                child: Text(
                                  'Keep me signed in',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                              TextButton(
                                onPressed: () => showDialog<void>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Demo sign-in help'),
                                    content: const Text(
                                      'Use a demo account with the password Nascon@26. Password reset will be available when a backend is connected.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(c),
                                        child: const Text('Got it'),
                                      ),
                                    ],
                                  ),
                                ),
                                child: const Text(
                                  'Need help?',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          PrimaryButton(
                            label: busy ? 'Signing in…' : 'Log in',
                            onPressed: busy ? null : login,
                            icon: busy
                                ? Icons.hourglass_top
                                : Icons.arrow_forward_rounded,
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: accounts,
                            icon: const Icon(Icons.groups_outlined),
                            label: const Text('Explore with a demo account'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 52),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Local demo · No backend connection required',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xff637151),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                openPage(context, const SettingsScreen()),
                            icon: const Icon(Icons.tune_rounded, size: 18),
                            label: const Text('Connection settings'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int selected = 0;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) => LayoutBuilder(
      builder: (context, c) {
        final pages = [
          Dashboard(onTab: (i) => setState(() => selected = i)),
          const FixturesScreen(),
          const StandingsScreen(),
          const StoreScreen(),
          const ProfileScreen(),
        ];
        const icons = [
          Icons.home_outlined,
          Icons.calendar_month_outlined,
          Icons.leaderboard_outlined,
          Icons.shopping_bag_outlined,
          Icons.person_outline,
        ];
        const labels = ['Home', 'Fixtures', 'Standings', 'Store', 'Profile'];
        final wide = c.maxWidth >= 720;
        return Scaffold(
          body: Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: selected,
                  onDestinationSelected: (i) => setState(() => selected = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: List.generate(
                    5,
                    (i) => NavigationRailDestination(
                      icon: Icon(icons[i]),
                      label: Text(labels[i]),
                    ),
                  ),
                ),
              Expanded(child: pages[selected]),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: selected,
                  onDestinationSelected: (i) => setState(() => selected = i),
                  height: 72,
                  destinations: List.generate(
                    5,
                    (i) => NavigationDestination(
                      icon: Badge(
                        isLabelVisible: i == 3 && app.cartCount > 0,
                        label: Text('${app.cartCount}'),
                        child: Icon(icons[i]),
                      ),
                      label: labels[i],
                    ),
                  ),
                ),
        );
      },
    ),
  );
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key, required this.onTab});
  final ValueChanged<int> onTab;
  @override
  Widget build(BuildContext context) {
    final match = app.matches.first;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const ConnectionStrip(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(22, 22, 16, 24),
                      decoration: const BoxDecoration(
                        gradient: brandGradient,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(32),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Colors.white,
                                child: Icon(
                                  Icons.sports_soccer,
                                  color: brandInk,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Your sports community',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      'Alpha Sports',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Pending actions',
                                onPressed: () =>
                                    openPage(context, const SyncScreen()),
                                icon: Badge(
                                  isLabelVisible: app.pendingCount > 0,
                                  label: Text('${app.pendingCount}'),
                                  child: const Icon(
                                    Icons.notifications_none_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Game on,\n${app.displayName}.',
                                      style: const TextStyle(
                                        fontSize: 33,
                                        height: 1.1,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: -1,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      demoRoles[app.role]!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                      onPressed: () => onTab(1),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: brandInk,
                                      ),
                                      icon: const Icon(Icons.arrow_forward_rounded,size:18),
                                      label: const Text('View fixtures'),
                                    ),
                                  ],
                                ),
                              ),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(90),
                                child: const SportsArtwork(size: 155),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionTitle(
                            'Happening now',
                            action: 'All fixtures',
                            onAction: () => onTab(1),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(22),
                            onTap: () => openPage(
                              context,
                              MatchDetailScreen(match: match),
                            ),
                            child: SoftCard(
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.circle,
                                        size: 8,
                                        color: Color(0xffbd4429),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        match.status == 'Live'
                                            ? 'LIVE · 62 min'
                                            : match.status,
                                        style: const TextStyle(
                                          color: Color(0xff9b3825),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const Spacer(),
                                      const Flexible(
                                        child: Text(
                                          'Football · Premier League',
                                          textAlign: TextAlign.end,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: brandInk,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 22),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _team(match.home),
                                      Expanded(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            '${match.homeScore} : ${match.awayScore}',
                                            style: const TextStyle(
                                              fontSize: 34,
                                              fontWeight: FontWeight.w900,
                                              color: brandInk,
                                            ),
                                          ),
                                        ),
                                      ),
                                      _team(match.away),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  const Divider(),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on_outlined,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          match.venue,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      const Text(
                                        'Match centre',
                                        style: TextStyle(
                                          color: brandInk,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right, size: 18),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SectionTitle('Your matchday essentials'),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _shortcut(
                                'Standings',
                                Icons.leaderboard_outlined,
                                () => onTab(2),
                              ),
                              _shortcut(
                                'My club',
                                Icons.shield_outlined,
                                () => openPage(context, const ClubScreen()),
                              ),
                              if (app.canManage)
                                _shortcut(
                                  'Manage roster',
                                  Icons.groups_outlined,
                                  () => openPage(context, const RosterScreen()),
                                ),
                              if (app.canScore)
                                _shortcut(
                                  'Enter score',
                                  Icons.sports_score,
                                  () => openPage(
                                    context,
                                    ScoringScreen(match: match),
                                  ),
                                ),
                              _shortcut(
                                'Sync queue',
                                Icons.sync,
                                () => openPage(context, const SyncScreen()),
                              ),
                            ],
                          ),
                          SectionTitle(
                            'Wear your team',
                            action: 'Shop all',
                            onAction: () => onTab(3),
                          ),
                          InkWell(
                            onTap: () => openPage(
                              context,
                              ProductScreen(product: app.products.first),
                            ),
                            borderRadius: BorderRadius.circular(22),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xffe5edce),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Made for\nthe Falcons.',
                                          style: TextStyle(
                                            fontSize: 25,
                                            fontWeight: FontWeight.w900,
                                            color: brandInk,
                                            height: 1.15,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'Your home jersey. Your club pride.',
                                          style: TextStyle(
                                            color: brandInk,
                                            fontSize: 12,
                                          ),
                                        ),
                                        SizedBox(height: 10),
                                        Text(
                                          'Shop the kit →',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: brandInk,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Transform.rotate(
                                    angle: -.12,
                                    child: const Icon(
                                      Icons.checkroom_rounded,
                                      size: 105,
                                      color: brandInk,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Fixtures and people shown are local demonstration data.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xff637151),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _team(String name) => SizedBox(
    width: 86,
    child: Column(
      children: [
        TeamBadge(name: name, size: 48),
        const SizedBox(height: 8),
        Text(
          name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ],
    ),
  );
  Widget _shortcut(String label, IconData icon, VoidCallback onTap) =>
      ActionChip(
        avatar: Icon(icon, size: 19, color: brandInk),
        label: Text(label),
        onPressed: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      );
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) => PageScaffold(
    title: 'Your profile',
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SoftCard(
          child: Column(
            children: [
              CircleAvatar(
                radius: 35,
                backgroundColor: const Color(0xffe1edca),
                child: Icon(roleIcon(app.role), size: 36, color: brandInk),
              ),
              const SizedBox(height: 14),
              Text(
                app.displayName,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(
                demoRoles[app.role]!,
                style: const TextStyle(
                  color: brandInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(app.email),
              const SizedBox(height: 14),
              const Chip(label: Text('Alpha Sports · Demo account')),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _row(
                context,
                Icons.shield_outlined,
                'My club',
                'Alpha Falcons',
                const ClubScreen(),
              ),
              if (app.canManage)
                _row(
                  context,
                  Icons.groups_outlined,
                  'Roster management',
                  'Manage your squad',
                  const RosterScreen(),
                ),
              if (app.canScore)
                _row(
                  context,
                  Icons.sports_score,
                  'Scoring desk',
                  'Enter or correct match events',
                  ScoringScreen(match: app.matches.first),
                ),
              _row(
                context,
                Icons.receipt_long_outlined,
                'My orders',
                'Receipts and order history',
                const OrdersScreen(),
              ),
              _row(
                context,
                Icons.sync,
                'Sync & offline',
                '${app.pendingCount} actions pending',
                const SyncScreen(),
              ),
              _row(
                context,
                Icons.tune_rounded,
                'Settings',
                'Server address and demo connection',
                const SettingsScreen(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () async {
            await app.logout();
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            }
          },
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
        ),
      ],
    ),
  );
  Widget _row(
    BuildContext c,
    IconData i,
    String title,
    String subtitle,
    Widget page,
  ) => ListTile(
    leading: Icon(i, color: brandInk),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => openPage(c, page),
  );
}

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) => PageScaffold(
      title: 'Sync & offline',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  app.online
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  color: brandInk,
                  size: 36,
                ),
                const SizedBox(height: 14),
                Text(
                  app.online ? 'You’re connected' : 'Your game goes on',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  app.online
                      ? 'Sync queued scores and roster moves with this device’s local demo.'
                      : 'Fixtures, standings and club profiles stay available. Scores and roster moves are saved until you reconnect.',
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Demo offline mode'),
                  subtitle: const Text(
                    'Try the offline flow without changing Wi-Fi',
                  ),
                  value: !app.online,
                  onChanged: (v) => app.setOnline(!v),
                ),
                const SizedBox(height: 10),
                PrimaryButton(
                  label: app.syncing
                      ? 'Syncing…'
                      : 'Sync ${app.pendingCount} pending actions',
                  icon: Icons.sync,
                  onPressed: !app.online || app.syncing || app.pendingCount == 0
                      ? null
                      : () => app.sync(),
                ),
              ],
            ),
          ),
          const SectionTitle('Action queue'),
          if (app.pending.isEmpty)
            const SoftCard(
              child: Column(
                children: [
                  Icon(Icons.task_alt, size: 42, color: brandInk),
                  SizedBox(height: 12),
                  Text(
                    'All caught up',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Queued scores and roster actions will appear here.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          for (final action in app.pending.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SoftCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      action.status == 'applied'
                          ? Icons.check_circle_outline
                          : action.status == 'rejected'
                          ? Icons.error_outline
                          : Icons.schedule,
                      color: action.status == 'rejected'
                          ? const Color(0xffa33320)
                          : brandInk,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            action.description,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${action.status[0].toUpperCase()}${action.status.substring(1)} · ${action.result}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            action.queuedAt
                                .substring(0, 16)
                                .replaceFirst('T', ' '),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xff637151),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Local demonstration sync. Backend conflict resolution will be connected in the integration phase.',
            style: TextStyle(fontSize: 12, color: Color(0xff637151)),
          ),
        ],
      ),
    ),
  );
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  final url = TextEditingController(text: app.serverUrl);
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) => PageScaffold(
      title: 'Settings',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SoftCard(
            child: Row(
              children: [
                Icon(Icons.science_outlined, color: brandInk, size: 30),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Demo mode is active. All app features use local sample data.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Backend connection',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Save the address for the upcoming integration. This frontend does not call a server yet.',
          ),
          const SizedBox(height: 16),
          Form(
            key: form,
            child: TextFormField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
              validator: (v) {
                final uri = Uri.tryParse(v ?? '');
                return uri == null ||
                        !['http', 'https'].contains(uri.scheme) ||
                        uri.host.isEmpty
                    ? 'Enter a URL such as http://10.0.2.2:8080'
                    : null;
              },
            ),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'Save address',
            icon: Icons.check,
            onPressed: () async {
              if (form.currentState!.validate()) {
                await app.setServer(url.text.trim());
                if (context.mounted) {
                  message(
                    context,
                    'Server address saved for future integration.',
                  );
                }
              }
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'Android emulator: http://10.0.2.2:8080\nPhysical phone: your backend laptop’s LAN IP',
            style: TextStyle(fontSize: 12, color: Color(0xff637151)),
          ),
          const SizedBox(height: 28),
          SoftCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Demo offline mode'),
              subtitle: const Text('Queue scores and roster changes locally'),
              value: !app.online,
              onChanged: (v) => app.setOnline(!v),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'NaSCon Sports · Part I\nLocal frontend preview',
            textAlign: TextAlign.center,
            style: TextStyle(color: brandInk),
          ),
        ],
      ),
    ),
  );
}
