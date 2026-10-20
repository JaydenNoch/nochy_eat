import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Form tambah / ubah menu makanan milik toko.
///
/// [product] null = menu baru, kalau ada = mode ubah.
/// Mengembalikan `true` bila berhasil disimpan.
class ProductFormView extends StatefulWidget {
  final String storeId;
  final Map<String, dynamic>? product;

  const ProductFormView({super.key, required this.storeId, this.product});

  @override
  State<ProductFormView> createState() => _ProductFormViewState();
}

class _ProductFormViewState extends State<ProductFormView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _priceController;
  late final TextEditingController _discountController;
  late final TextEditingController _stockController;
  late final TextEditingController _imageController;

  bool _isSaving = false;

  /// Kategori menu: menentukan di tab sidebar mana menu ini dipajang di
  /// halaman detail toko. Isinya harus sama dengan values di
  /// products_category_check (lihat supabase/driver_setup.sql bagian 18).
  /// 'flash_sale' sengaja tidak ada di sini karena kategori itu diisi
  /// otomatis dari menu yang punya harga diskon.
  static const Map<String, String> _categoryOptions = {
    'rekomendasi': 'Rekomendasi',
    'makanan': 'Makanan',
    'minuman': 'Minuman',
    'snack': 'Snack',
  };

  /// Bisa berisi lebih dari satu kategori, misal Makanan + Minuman.
  late List<String> _categories;

  bool get _isEdit => widget.product != null;

  List<String> _readSavedCategories() {
    final raw = widget.product?['category'];
    final saved = <String>[
      if (raw is List) ...raw.map((e) => e.toString()),
      if (raw is String && raw.isNotEmpty) raw,
    ].where(_categoryOptions.containsKey).toList();

    // Menu lama yang belum pernah dikategorikan tetap diberi satu
    // kategori supaya tidak lenyap dari tampilan customer.
    return saved.isEmpty ? ['makanan'] : saved;
  }

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _categories = _readSavedCategories();
    _nameController = TextEditingController(text: p?['name'] as String? ?? '');
    _descController = TextEditingController(text: p?['description'] as String? ?? '');
    _priceController = TextEditingController(
      text: p?['price'] == null ? '' : (p!['price'] as num).toStringAsFixed(0),
    );
    _discountController = TextEditingController(
      text: p?['discount_price'] == null
          ? ''
          : (p!['discount_price'] as num).toStringAsFixed(0),
    );
    _stockController = TextEditingController(
      text: '${(p?['stock'] as num?)?.toInt() ?? 0}',
    );
    _imageController = TextEditingController(text: p?['image_url'] as String? ?? '');

    // Listener untuk memperbarui preview gambar secara real-time saat URL diketik
    _imageController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    _stockController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih minimal satu kategori untuk menu ini.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final price = double.parse(_priceController.text.trim());
    final discountText = _discountController.text.trim();
    final stock = int.parse(_stockController.text.trim());

    final payload = {
      'name': _nameController.text.trim(),
      'description': _descController.text.trim().isEmpty ? null : _descController.text.trim(),
      'price': price,
      'discount_price': discountText.isEmpty ? null : double.parse(discountText),
      'stock': stock,
      // Stok habis otomatis membuat menu tidak tersedia di sisi customer.
      'is_available': stock > 0,
      'category': _categories,
      'image_url': _imageController.text.trim().isEmpty ? null : _imageController.text.trim(),
    };

    try {
      if (_isEdit) {
        await _supabase.from('products').update(payload).eq('id', widget.product!['id']);
      } else {
        await _supabase.from('products').insert({...payload, 'store_id': widget.storeId});
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan menu: $e')),
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
          _isEdit ? 'Ubah Menu' : 'Tambah Menu',
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
            // INFORMASI DASAR
            const Text(
              'Informasi Dasar',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _nameController,
              decoration: _decoration('Nama Menu', 'mis. Nasi Goreng Spesial'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama menu wajib diisi' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descController,
              maxLines: 2,
              decoration: _decoration('Deskripsi (Opsional)', 'Bahan, porsi, catatan'),
            ),
            const SizedBox(height: 20),

            // HARGA & STOK
            const Text(
              'Harga & Ketersediaan',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _decoration('Harga Normal', '25000').copyWith(prefixText: 'Rp '),
                    validator: (v) {
                      final value = double.tryParse(v?.trim() ?? '');
                      if (value == null || value <= 0) return 'Harga > 0';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _stockController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _decoration('Stok Porsi', '20'),
                    validator: (v) {
                      final value = int.tryParse(v?.trim() ?? '');
                      if (value == null || value < 0) return 'Stok minimal 0';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _discountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _decoration('Harga Diskon (Opsional)', 'Kosongkan jika tidak ada').copyWith(prefixText: 'Rp '),
              validator: (v) {
                final text = v?.trim() ?? '';
                if (text.isEmpty) return null;
                final discount = double.tryParse(text);
                final price = double.tryParse(_priceController.text.trim());
                if (discount == null || discount <= 0) return 'Diskon tidak valid';
                if (price != null && discount >= price) {
                  return 'Harus lebih murah dari harga normal';
                }
                return null;
              },
            ),
            const SizedBox(height: 4),
            Text(
              'Stok 0 akan otomatis menandai menu sebagai "Habis" bagi pelanggan. '
              'Isi harga diskon kalau menu ini mau ikut promo — menu otomatis '
              'muncul di Flash Sale dengan harga coret.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),

            // KATEGORI
            const Text(
              'Kategori Menu',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark),
            ),
            const SizedBox(height: 4),
            Text(
              'Menentukan posisi menu di halaman detail toko pelanggan. '
              'Boleh pilih lebih dari satu, misal Makanan sekaligus Minuman. '
              'Kategori Flash Sale terisi sendiri dari menu yang punya harga diskon.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categoryOptions.entries.map((option) {
                final bool isSelected = _categories.contains(option.key);
                return FilterChip(
                  label: Text(option.value),
                  selected: isSelected,
                  selectedColor: AppColors.primaryPink.withValues(alpha: 0.1),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? AppColors.primaryPink : AppColors.textDark,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isSelected ? AppColors.primaryPink : Colors.grey.shade300,
                      width: isSelected ? 1.2 : 1,
                    ),
                  ),
                  showCheckmark: false,
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _categories.add(option.key);
                    } else {
                      _categories.remove(option.key);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // GAMBAR MENU
            const Text(
              'Foto Menu',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _imageController,
              decoration: _decoration('URL Gambar Menu (Opsional)', 'https://.../foto-menu.jpg'),
            ),
            const SizedBox(height: 10),
            if (_imageController.text.trim().isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
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
                  _isEdit ? 'Simpan Perubahan' : 'Tambah Menu',
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

  InputDecoration _decoration(String label, String hint) {
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