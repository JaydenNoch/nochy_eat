import 'package:flutter/material.dart';
import 'package:nochy_eat/views/customer/customer_profile_view.dart';
import 'package:nochy_eat/views/universal/login_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileTabWrapper extends StatefulWidget {
  final VoidCallback? onLoginSuccess;

  const ProfileTabWrapper({super.key, this.onLoginSuccess});

  @override
  State<ProfileTabWrapper> createState() => _ProfileTabWrapperState();
}

class _ProfileTabWrapperState extends State<ProfileTabWrapper> {
  final SupabaseClient _supabase = Supabase.instance.client;
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = _supabase.auth.currentUser;

    // Mendengarkan perubahan status login/logout secara realtime
    _supabase.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() {
          _currentUser = data.session?.user;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return LoginView(
        onLoginSuccess: () {
          setState(() {
            _currentUser = _supabase.auth.currentUser;
          });
          // Notify parent (CustomerHomeView) agar reload alamat
          widget.onLoginSuccess?.call();
        },
      );
    }

    return const CustomerProfileView();
  }
}