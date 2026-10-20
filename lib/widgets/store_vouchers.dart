import 'package:flutter/material.dart';
import 'package:nochy_eat/models/app_models.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Baris voucher milik toko yang dibuat seller.
///
/// Voucher aktif otomatis tersedia di keranjang/checkout toko ini, jadi
/// pembeli cukup melihatnya sebagai informasi.
class StoreVouchers extends StatefulWidget {
  final String storeId;

  const StoreVouchers({super.key, required this.storeId});

  @override
  State<StoreVouchers> createState() => _StoreVouchersState();
}

class _StoreVouchersState extends State<StoreVouchers> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<StoreVoucherModel> _vouchers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final data = await _supabase
          .from('store_vouchers')
          .select()
          .eq('store_id', widget.storeId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      if (!mounted) return;
      List<StoreVoucherModel> vouchers =
          (data as List).map((e) => StoreVoucherModel.fromJson(e)).toList();

      // Buang voucher yang sudah pernah dipakai user ini: satu voucher
      // toko hanya berlaku satu kali per user.
      final user = _supabase.auth.currentUser;
      if (user != null && vouchers.isNotEmpty) {
        try {
          final used = await _supabase
              .from('store_voucher_usages')
              .select('store_voucher_id')
              .eq('user_id', user.id);
          final usedIds = (used as List)
              .map((e) => e['store_voucher_id'].toString())
              .toSet();
          vouchers = vouchers
              .where((v) => !usedIds.contains(v.id))
              .toList();
        } catch (_) {
          // Tabel catatan belum dibuat (SQL belum dijalankan):
          // biarkan semua voucher tampil seperti biasa.
        }
      }

      setState(() {
        _vouchers = vouchers;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showVoucherDetails(StoreVoucherModel voucher) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Detail Voucher',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(voucher.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Text(voucher.shortLabel,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.primaryPink, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(voucher.minOrderLabel,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            if (voucher.description != null &&
                voucher.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(voucher.description!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const SizedBox(height: 12),
            const Text(
              'Voucher bisa dipilih saat kamu checkout di toko ini.',
              style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _vouchers.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: _vouchers.map(_buildVoucherChip).toList(),
      ),
    );
  }

  Widget _buildVoucherChip(StoreVoucherModel voucher) {
    return InkWell(
      onTap: () => _showVoucherDetails(voucher),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primaryPink.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.primaryPink.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.confirmation_num_outlined,
                color: AppColors.primaryPink, size: 16),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(voucher.shortLabel,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryPink)),
                Text(
                  voucher.minOrder > 0
                      ? 'Min. Rp${voucher.minOrder.toStringAsFixed(0)}'
                      : 'Tanpa min.',
                  style: const TextStyle(fontSize: 8, color: AppColors.textDark),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
