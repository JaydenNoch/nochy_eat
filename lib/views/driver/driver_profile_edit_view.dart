import 'package:flutter/material.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/driver_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Layar edit profil driver. Data disimpan ke tabel `profiles`,
/// jadi nomor HP yang diisi pembeli saat checkout bisa dipakai
/// driver untuk menghubungi mereka.
class DriverProfileEditView extends StatefulWidget {
  const DriverProfileEditView({super.key});

  @override
  State<DriverProfileEditView> createState() => _DriverProfileEditViewState();
}

class _DriverProfileEditViewState extends State<DriverProfileEditView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _avatarController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _isLoading = false;
        _error = 'Belum login.';
      });
      return;
    }

    try {
      final row = await _supabase
          .from('profiles')
          .select('full_name, phone, address, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _nameController.text = row?['full_name']?.toString() ?? '';
        _phoneController.text = row?['phone']?.toString() ?? '';
        _addressController.text = row?['address']?.toString() ?? '';
        _avatarController.text = row?['avatar_url']?.toString() ?? '';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);
    try {
      await _supabase.from('profiles').update({
        'full_name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'avatar_url': _avatarController.text.trim().isEmpty
            ? null
            : _avatarController.text.trim(),
      }).eq('id', user.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil driver tersimpan.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan profil: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLightGrey,
      appBar: AppBar(
        backgroundColor: AppColors.bgWhite,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: AppColors.textDark),
        title: const Text(
          'Edit Profil Driver',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryPink),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Gagal memuat profil: $_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Data ini dipakai pelanggan saat menghubungi driver.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      _buildField(
                        controller: _nameController,
                        label: 'Nama Lengkap',
                        hint: 'Contoh: Bayu Pratama',
                        icon: Icons.badge_outlined,
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Nama wajib diisi' : null,
                      ),
                      const SizedBox(height: 14),
                      _buildField(
                        controller: _phoneController,
                        label: 'Nomor HP',
                        hint: 'Contoh: 081234567890',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return 'Nomor HP wajib diisi';
                          if (value.length < 9) return 'Nomor HP terlalu pendek';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      _buildField(
                        controller: _addressController,
                        label: 'Alamat (opsional)',
                        hint: 'Domisili / area operasional driver',
                        icon: Icons.home_outlined,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 14),
                      _buildField(
                        controller: _avatarController,
                        label: 'URL Foto Profil (opsional)',
                        hint: 'Tempel URL foto profilmu di sini',
                        icon: Icons.image_outlined,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryPink,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: const BorderRadius.all(DriverUi.controlRadius),
                            ),
                          ),
                          onPressed: _isSaving ? null : _save,
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Simpan Perubahan',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: AppColors.primaryPink, size: 20),
            filled: true,
            fillColor: AppColors.bgWhite,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: const BorderRadius.all(DriverUi.controlRadius),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(DriverUi.controlRadius),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: const BorderRadius.all(DriverUi.controlRadius),
              borderSide: const BorderSide(color: AppColors.primaryPink),
            ),
          ),
        ),
      ],
    );
  }
}
