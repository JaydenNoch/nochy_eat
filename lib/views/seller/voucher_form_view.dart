import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Form tambah / ubah voucher yang dibuat seller untuk tokonya.
///
/// [voucher] null = voucher baru, kalau ada = mode ubah.
/// Mengembalikan `true` bila berhasil disimpan.
class VoucherFormView extends StatefulWidget {
  final String storeId;
  final Map<String, dynamic>? voucher;

  const VoucherFormView({super.key, required this.storeId, this.voucher});

  @override
  State<VoucherFormView> createState() => _VoucherFormViewState();
}

class _VoucherFormViewState extends State<VoucherFormView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _codeController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _valueController;
  late final TextEditingController _maxDiscountController;
  late final TextEditingController _minOrderController;

  String _discountType = 'percent';
  bool _isActive = true;
  bool _isSaving = false;

  bool get _isEdit => widget.voucher != null;

  @override
  void initState() {
    super.initState();
    final v = widget.voucher;
    _titleController = TextEditingController(text: v?['title'] as String? ?? '');
    _codeController = TextEditingController(text: v?['code'] as String? ?? '');
    _descriptionController =
        TextEditingController(text: v?['description'] as String? ?? '');
    _valueController = TextEditingController(
      text: v?['discount_value'] == null
          ? ''
          : (v!['discount_value'] as num).toStringAsFixed(0),
    );
    _maxDiscountController = TextEditingController(
      text: v?['max_discount'] == null
          ? ''
          : (v!['max_discount'] as num).toStringAsFixed(0),
    );
    _minOrderController = TextEditingController(
      text: v?['min_order'] == null
          ? '0'
          : (v!['min_order'] as num).toStringAsFixed(0),
    );
    if (v?['discount_type'] != null) {
      _discountType = v!['discount_type'] as String;
    }
    if (v?['is_active'] != null) {
      _isActive = v!['is_active'] == true;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _codeController.dispose();
    _descriptionController.dispose();
    _valueController.dispose();
    _maxDiscountController.dispose();
    _minOrderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final value = double.parse(_valueController.text.trim());
    final maxDiscountText = _maxDiscountController.text.trim();
    final minOrder = double.tryParse(_minOrderController.text.trim()) ?? 0;

    var code = _codeController.text.trim().toUpperCase().replaceAll(' ', '');
    if (code.isEmpty) {
      code = 'SALE${DateTime.now().millisecondsSinceEpoch % 100000}';
    }

    final payload = {
      'title': _titleController.text.trim(),
      'code': code,
      'description': _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      'discount_type': _discountType,
      'discount_value': value,
      'max_discount':
      maxDiscountText.isEmpty ? null : double.parse(maxDiscountText),
      'min_order': minOrder,
      'is_active': _isActive,
    };

    try {
      if (_isEdit) {
        await _supabase
            .from('store_vouchers')
            .update(payload)
            .eq('id', widget.voucher!['id']);
      } else {
        await _supabase
            .from('store_vouchers')
            .insert({...payload, 'store_id': widget.storeId});
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan voucher: $e'), backgroundColor: Colors.red),
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
          _isEdit ? 'Ubah Voucher' : 'Buat Voucher',
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
            // INFORMASI UTAMA
            const Text(
              'Informasi Voucher',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _titleController,
              decoration: _decoration('Nama Voucher', 'mis. Diskon 20% Makan Malam'),
              validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Nama voucher wajib diisi' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _discountType,
              decoration: _decoration('Jenis Diskon', ''),
              items: const [
                DropdownMenuItem(value: 'percent', child: Text('Diskon Persen (%)')),
                DropdownMenuItem(value: 'fixed', child: Text('Potongan Harga (Rp)')),
                DropdownMenuItem(value: 'free_delivery', child: Text('Gratis Ongkir (Rp)')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _discountType = value);
              },
            ),
            const SizedBox(height: 20),

            // PENGATURAN NILAI & KETENTUAN
            const Text(
              'Nilai & Ketentuan',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _valueController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _decoration(
                _discountType == 'percent' ? 'Besaran Diskon (%)' : 'Besaran Diskon (Rp)',
                _discountType == 'percent' ? '20' : '5000',
              ).copyWith(prefixText: _discountType == 'percent' ? null : 'Rp '),
              validator: (v) {
                final value = double.tryParse(v?.trim() ?? '');
                if (value == null || value <= 0) return 'Besaran diskon harus lebih dari 0';
                if (_discountType == 'percent' && value > 100) {
                  return 'Diskon persen maksimal 100';
                }
                return null;
              },
            ),
            if (_discountType == 'percent') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _maxDiscountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _decoration('Maksimal Potongan (Opsional)', 'mis. 20000')
                    .copyWith(prefixText: 'Rp '),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _minOrderController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _decoration('Minimal Belanja', '0').copyWith(prefixText: 'Rp '),
            ),
            const SizedBox(height: 20),

            // KODE & KETERANGAN TAMBAHAN
            const Text(
              'Kode & Keterangan',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: _decoration('Kode Voucher (Opsional)', 'Kosongkan untuk otomatis'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: _decoration('Keterangan / S&K (Opsional)', 'Syarat & ketentuan berlaku'),
            ),
            const SizedBox(height: 16),

            // STATUS AKTIF SWITCH
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300, width: 1),
              ),
              child: SwitchListTile(
                value: _isActive,
                activeColor: Colors.green,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                onChanged: (value) => setState(() => _isActive = value),
                title: const Text('Voucher Aktif',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark)),
                subtitle: Text(
                  _isActive
                      ? 'Voucher tampil dan bisa dipakai pembeli.'
                      : 'Voucher disembunyikan dari pembeli.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
                  _isEdit ? 'Simpan Perubahan' : 'Buat Voucher',
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
      hintText: hint.isEmpty ? null : hint,
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