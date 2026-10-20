import 'package:flutter/material.dart';
import 'package:nochy_eat/services/auth_state.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginView extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginView({super.key, required this.onLoginSuccess});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();

  String _selectedRole = 'customer';
  bool _isRegister = false; // Default ke mode Login
  bool _isLoading = false;
  bool _obscurePassword = true;

  // State untuk menampilkan halaman sukses register
  bool _registerSuccess = false;
  String _registeredEmail = '';
  String _registeredRole = '';

  @override
  void initState() {
    super.initState();
    // Cek apakah ada data register sukses dari sebelumnya
    // (karena RoleRouter bisa rebuild & bikin LoginView baru)
    if (RegisterSuccessData.success) {
      _registerSuccess = true;
      _registeredEmail = RegisterSuccessData.email;
      _registeredRole = RegisterSuccessData.role;
      RegisterSuccessData.clear();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _submitAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final fullName = _fullNameController.text.trim();
    final currentRole = _selectedRole;

    try {
      if (_isRegister) {
        // 1. Panggil signUp standar Supabase
        final AuthResponse response = await _supabase.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': fullName, 'role': currentRole},
        );

        if (response.user != null) {
          // Simpan profil ke tabel profiles
          try {
            await _supabase.from('profiles').upsert({
              'id': response.user!.id,
              'full_name': fullName,
              'role': currentRole,
              'coins_balance': 0.0,
            });
          } catch (dbError) {
            print("Database profile insert skipped: $dbError");
          }

          // Simpan info sukses ke global state SEBELUM signOut
          // (karena signOut akan trigger RoleRouter rebuild & bikin LoginView baru)
          RegisterSuccessData.set(email, currentRole);

          // Sign out agar tidak auto-redirect ke home oleh RoleRouter
          isHoldingRegisterState = true;
          await _supabase.auth.signOut();
          isHoldingRegisterState = false;

          if (mounted) {
            setState(() {
              _isLoading = false;
              _registerSuccess = true;
              _registeredEmail = email;
              _registeredRole = currentRole;
              _emailController.clear();
              _passwordController.clear();
              _fullNameController.clear();
            });
          }
        }
      } else {
        // --- PROSES LOGIN ---
        final AuthResponse response = await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (response.user != null && mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Login berhasil! 👋'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onLoginSuccess();
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        String errorMessage = e.message;

        // Tangkap jika email sudah terdaftar
        if (errorMessage.contains('already registered') ||
            errorMessage.contains('already exists') ||
            errorMessage.contains('User already registered')) {
          errorMessage = 'Akun dengan email ini sudah terdaftar! Silakan gunakan email lain.';
        }

        // Tampilkan Alert Gagal / Email Sudah Terdaftar & Tetap di Register
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 28),
                SizedBox(width: 8),
                Text('Perhatian', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(errorMessage, style: const TextStyle(fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK', style: TextStyle(color: AppColors.primaryPink, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Terjadi kesalahan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Jika register berhasil, tampilkan halaman sukses inline
    if (_registerSuccess) {
      return Scaffold(
        backgroundColor: AppColors.bgWhite,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Ikon centang besar
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      size: 80,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 28),

                  const Text(
                    'AKUN SUDAH TERBUAT 🎉',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text(
                    'Akun ${_registeredRole.toUpperCase()} dengan email',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _registeredEmail,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryPink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'sudah berhasil terbuat!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 32),

                  // Tombol ke halaman login
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryPink,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        setState(() {
                          _registerSuccess = false;
                          _isRegister = false; // Pindah ke mode login
                        });
                      },
                      icon: const Icon(Icons.login),
                      label: const Text(
                        'Masuk Sekarang',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tombol buat akun lagi
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _registerSuccess = false;
                        _isRegister = true; // Tetap di mode register
                      });
                    },
                    child: const Text(
                      'Buat akun lain',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),

                // --- LOGO / HEADER ---
                Center(
                  child: Column(
                    children: [
                      Image.asset(
                        'lib/theme/logoeat.png',
                        width: 110,
                        height: 110,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isRegister
                            ? 'Buat Akun NOCHY E-AT '
                            : 'Masuk ke NOCHY E-AT ',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isRegister
                            ? 'Daftar sebagai Pelanggan, Driver, atau Toko!'
                            : 'Silakan masuk dengan email dan kata sandi Anda.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                // --- FIELD NAMA LENGKAP (Hanya saat Register) ---
                if (_isRegister) ...[
                  TextFormField(
                    controller: _fullNameController,
                    decoration: InputDecoration(
                      labelText: 'Nama Lengkap',
                      prefixIcon: const Icon(Icons.person_outline,
                          color: AppColors.primaryPink),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: AppColors.primaryPink, width: 2),
                      ),
                    ),
                    validator: (val) {
                      if (_isRegister && (val == null || val.trim().isEmpty)) {
                        return 'Nama lengkap harus diisi';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // --- DROPDOWN PILIHAN PERAN (ROLE) ---
                  DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    decoration: InputDecoration(
                      labelText: 'Daftar Sebagai',
                      prefixIcon: const Icon(Icons.badge_outlined,
                          color: AppColors.primaryPink),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: AppColors.primaryPink, width: 2),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'customer',
                        child: Text('Pelanggan (Customer) 🛍️'),
                      ),
                      DropdownMenuItem(
                        value: 'driver',
                        child: Text('Driver Pengantar 🛵'),
                      ),
                      DropdownMenuItem(
                        value: 'seller',
                        child: Text('Mitra Toko / Resto 🏪'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedRole = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // --- FIELD EMAIL ---
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email_outlined,
                        color: AppColors.primaryPink),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: AppColors.primaryPink, width: 2),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Email harus diisi';
                    }
                    if (!val.contains('@')) return 'Format email tidak valid';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // --- FIELD PASSWORD ---
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Kata Sandi',
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: AppColors.primaryPink),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: AppColors.primaryPink, width: 2),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Kata sandi harus diisi';
                    }
                    if (val.length < 6) return 'Kata sandi minimal 6 karakter';
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // --- TOMBOL UTAMA ---
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPink,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _submitAuth,
                    child: _isLoading
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                        : Text(
                      _isRegister ? 'Daftar Sekarang' : 'Masuk',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // --- TOGGLE LOGIN / REGISTER ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isRegister ? 'Sudah punya akun?' : 'Belum punya akun?',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isRegister = !_isRegister;
                          _formKey.currentState?.reset();
                        });
                      },
                      child: Text(
                        _isRegister ? 'Masuk di sini' : 'Daftar sekarang',
                        style: const TextStyle(
                          color: AppColors.primaryPink,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}