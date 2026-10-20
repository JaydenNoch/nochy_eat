import 'package:flutter/material.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/widgets/location_picker_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Form buat / ubah profil toko milik seller yang sedang login.
///
/// [store] null = buat toko baru, kalau ada = mode ubah.
/// Mengembalikan `true` bila berhasil disimpan.
class StoreFormView extends StatefulWidget {
  final Map<String, dynamic>? store;

  const StoreFormView({super.key, this.store});

  @override
  State<StoreFormView> createState() => _StoreFormViewState();
}

class _StoreFormViewState extends State<StoreFormView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _imageController;

  double _latitude = -7.7956;
  double _longitude = 110.3695;
  bool _locationPicked = false;
  bool _isSaving = false;

  bool get _isEdit => widget.store != null;

  @override
  void initState() {
    super.initState();
    final store = widget.store;
    _nameController = TextEditingController(text: store?['store_name'] as String? ?? '');
    _addressController = TextEditingController(text: store?['address'] as String? ?? '');
    _imageController = TextEditingController(text: store?['image_url'] as String? ?? '');
    final lat = (store?['latitude'] as num?)?.toDouble();
    final lng = (store?['longitude'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      _latitude = lat;
      _longitude = lng;
      _locationPicked = true;
    }

    // Listener untuk memperbarui preview gambar secara real-time saat URL diketik
    _imageController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerView(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _latitude = (result['latitude'] as num).toDouble();
      _longitude = (result['longitude'] as num).toDouble();
      _locationPicked = true;
      final address = result['address'] as String?;
      if (address != null && address.isNotEmpty) {
        _addressController.text = address;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Titik peta wajib diambil. Tanpa ini toko memakai titik default
    // (-7.7956, 110.3695), dan pembeli melihat lokasi yang salah di
    // detail toko sekaligus di peta driver.
    if (!_locationPicked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tentukan dulu titik lokasi toko lewat tombol peta di kolom alamat.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isSaving = true);
    final payload = {
      'store_name': _nameController.text.trim(),
      'address': _addressController.text.trim(),
      'latitude': _latitude,
      'longitude': _longitude,
      'image_url': _imageController.text.trim().isEmpty ? null : _imageController.text.trim(),
    };

    try {
      if (_isEdit) {
        await _supabase.from('stores').update(payload).eq('id', widget.store!['id']);
      } else {
        await _supabase.from('stores').insert({
          ...payload,
          'merchant_id': user.id,
          'is_open': true,
          'rating': 0.0,
        });
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan toko: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLightGrey,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: true,
        iconTheme: const IconThemeData(color: AppColors.textDark),
        titleSpacing: 0,
        title: Text(
          _isEdit ? 'Ubah Profil Toko' : 'Buat Toko Baru',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textDark),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: Colors.grey.shade200,
            height: 1.0,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            // INFORMASI TOKO
            const Text(
              'Informasi Toko',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: _inputDecoration('Nama Toko', 'contoh: Warung Nasi Goreng Bu Sri'),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Nama toko wajib diisi' : null,
            ),
            const SizedBox(height: 20),

            // LOKASI & PETA
            const Text(
              'Lokasi & Alamat',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _addressController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Alamat Toko',
                hintText: 'Nama jalan / patokan lokasi',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primaryPink, width: 1.2),
                ),
                suffixIcon: IconButton(
                  tooltip: 'Pilih dari peta',
                  icon: const Icon(Icons.map_rounded, color: AppColors.primaryPink),
                  onPressed: _pickLocation,
                ),
              ),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Alamat toko wajib diisi' : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _locationPicked ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  size: 16,
                  color: _locationPicked ? Colors.green.shade700 : Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _locationPicked
                        ? 'Koordinat: ${_latitude.toStringAsFixed(4)},${_longitude.toStringAsFixed(4)}'
                        : 'Wajib: ambil titik peta lewat tombol peta di kolom alamat.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // FOTO TOKO
            const Text(
              'Foto Toko',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _imageController,
              decoration: _inputDecoration(
                'URL Gambar Toko (Opsional)',
                'https://.../foto-toko.jpg',
              ),
            ),
            const SizedBox(height: 10),
            if (_imageController.text.trim().isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.network(
                  _imageController.text.trim(),
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 80,
                    alignment: Alignment.center,
                    color: Colors.grey.shade100,
                    child: Text('Gagal memuat pratinjau gambar', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ),
                ),
              ),
            const SizedBox(height: 32),

            // TOMBOL SIMPAN
            SizedBox(
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPink,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
                    : Text(
                  _isEdit ? 'Simpan Perubahan' : 'Buat Toko',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
      labelStyle: TextStyle(fontSize: 13, color: Colors.grey.shade700),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primaryPink, width: 1.2),
      ),
    );
  }
}