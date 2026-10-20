import 'package:flutter/material.dart';
import 'package:nochy_eat/services/auth_state.dart';
import 'package:nochy_eat/views/driver/driver_home_view.dart';
import 'package:nochy_eat/views/universal/customer_home_view.dart';
import 'package:nochy_eat/views/seller/seller_home_view.dart';
import 'package:nochy_eat/widgets/nochy_loading_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://alyscsmdtmczulwahqby.supabase.co',
    anonKey: 'sb_publishable_VQKrHuNLNtBic4RLOf7y2w_YtFPum35',
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NOCHY E-AT',
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const RoleRouter(),
    );
  }
}

class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Paksa loading screen tampil minimal 2 detik
  final Future<void> _minDisplayTime =
      Future.delayed(const Duration(seconds: 2));
  bool _minTimeElapsed = false;

  @override
  void initState() {
    super.initState();
    _minDisplayTime.then((_) {
      if (mounted) setState(() => _minTimeElapsed = true);
    });
  }

  Future<String?> _getUserRole(User? user) async {
    if (user == null) return null;

    try {
      final response = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (response != null && response['role'] != null) {
        return response['role'].toString().toLowerCase();
      }
    } catch (e) {
      // Handle error
    }

    return 'customer';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        Widget page;

        if (isHoldingRegisterState) {
          page = const CustomerHomeView();
        } else if (!_minTimeElapsed ||
            snapshot.connectionState == ConnectionState.waiting) {
          // Belum 2 detik ATAU stream belum siap → tetap loading
          page = const NochyLoadingScreen();
        } else {
          final session = snapshot.data?.session ?? _supabase.auth.currentSession;

          if (session == null) {
            page = const CustomerHomeView();
          } else {
            page = FutureBuilder<String?>(
              future: _getUserRole(session.user),
              builder: (context, roleSnapshot) {
                if (roleSnapshot.connectionState == ConnectionState.waiting) {
                  return const NochyLoadingScreen();
                }
                final role = roleSnapshot.data ?? 'customer';
                if (role == 'driver') return const DriverHomeView();
                if (role == 'seller') return const SellerHomeView();
                return const CustomerHomeView();
              },
            );
          }
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          child: KeyedSubtree(
            key: ValueKey(page.runtimeType),
            child: page,
          ),
        );
      },
    );
  }
}