import 'package:flutter/material.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/customer_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VouchersView extends StatefulWidget {
  const VouchersView({super.key});

  @override
  State<VouchersView> createState() => _VouchersViewState();
}

class _VouchersViewState extends State<VouchersView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  Set<String> _claimedVoucherCodes = {};
  bool _isLoading = true;

  // Daftar voucher yang tersedia di Pusat Voucher
  final List<Map<String, dynamic>> _availableVouchers = [
    {
      'code': 'GRATISONGKIR10',
      'title': 'Gratis Ongkir s.d. Rp10.000',
      'minOrder': 'Min. Transaksi Rp30.000',
      'validity': 'Berlaku s.d. 31 Okt 2026',
      'tag': 'GRATIS ONGKIR',
      'bgColor': Colors.green.shade50,
      'tagColor': Colors.green,
    },
    {
      'code': 'NOCHY50',
      'title': 'Diskon Makanan 50% NOCHY DEALS',
      'minOrder': 'Min. Transaksi Rp25.000',
      'validity': 'Berlaku s.d. 25 Okt 2026',
      'tag': 'PROMO SPESIAL',
      'bgColor': AppColors.primaryPink.withValues(alpha: 0.1),
      'tagColor': AppColors.primaryPink,
    },
    {
      'code': 'NEWUSER15',
      'title': 'Voucher Pengguna Baru Rp15.000',
      'minOrder': 'Tanpa Min. Transaksi',
      'validity': 'Berlaku s.d. 15 Nov 2026',
      'tag': 'PENGGUNA BARU',
      'bgColor': Colors.blue.shade50,
      'tagColor': Colors.blue,
    },
    {
      'code': 'CASHBACK30',
      'title': 'Diskon CashBack NOCHY Coins 30%',
      'minOrder': 'Min. Transaksi Rp50.000',
      'validity': 'Berlaku s.d. 30 Okt 2026',
      'tag': 'CASHBACK',
      'bgColor': Colors.amber.shade50,
      'tagColor': Colors.amber.shade800,
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchClaimedVouchers();
  }

  /// Memeriksa voucher mana saja yang sudah diklaim pengguna di Supabase
  Future<void> _fetchClaimedVouchers() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final data = await _supabase
            .from('user_vouchers')
            .select('code')
            .eq('user_id', user.id);

        final Set<String> claimedCodes =
        (data as List).map((e) => e['code'].toString()).toSet();

        setState(() {
          _claimedVoucherCodes = claimedCodes;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  /// Fungsi untuk mengklaim voucher dan menyimpannya ke Supabase
  Future<void> _claimVoucher(Map<String, dynamic> voucher) async {
    final code = voucher['code'] as String;

    if (_claimedVoucherCodes.contains(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voucher ini sudah kamu klaim! Check di Voucher Saya 🎟️'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Silakan login terlebih dahulu')),
        );
        return;
      }

      // Simpan ke Supabase database
      await _supabase.from('user_vouchers').insert({
        'user_id': user.id,
        'title': voucher['title'],
        'code': voucher['code'],
        'min_order': voucher['minOrder'],
        'validity': voucher['validity'],
      });

      if (mounted) {
        setState(() {
          _claimedVoucherCodes.add(code);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voucher berhasil diklaim! Masuk ke Voucher Saya 🎟️'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengklaim voucher: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLightGrey,
      appBar: AppBar(
        backgroundColor: AppColors.bgWhite,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: Colors.grey.shade200,
            height: 1,
          ),
        ),
        title: const Text(
          'Pusat Voucher',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryPink))
          : SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryPink,
          onRefresh: _fetchClaimedVouchers,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: CustomerUi.surface(color: CustomerUi.pinkTint),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryPink.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.card_giftcard_rounded,
                          color: AppColors.primaryPink,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Voucher untuk pesananmu',
                              style: TextStyle(
                                color: AppColors.textDark,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Gunakan voucher saat checkout untuk makan lebih hemat.',
                              style: TextStyle(
                                color: AppColors.textDark.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                const Text(
                  'Voucher Tersedia',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 12),

                // Daftar Voucher
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _availableVouchers.length,
                  itemBuilder: (context, index) {
                    final v = _availableVouchers[index];
                    final isClaimed =
                    _claimedVoucherCodes.contains(v['code']);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.bgWhite,
                        borderRadius: const BorderRadius.all(CustomerUi.cardRadius),
                        border: Border.all(color: CustomerUi.border),
                      ),
                      child: Row(
                        children: [
                          // Tag Kiri
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: v['bgColor'],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.confirmation_number_rounded,
                                  color: v['tagColor'],
                                  size: 24,
                                ),
                                const SizedBox(height: 4),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  child: Text(
                                    v['tag'],
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: v['tagColor'],
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Detail Voucher
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  v['title'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  v['minOrder'],
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textDark
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  v['validity'],
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textDark
                                        .withValues(alpha: 0.4),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Tombol Klaim / Tersimpan
                          SizedBox(
                            height: 36,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isClaimed
                                    ? Colors.grey.shade100
                                    : AppColors.primaryPink,
                                foregroundColor: isClaimed
                                    ? Colors.grey.shade500
                                    : Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                              ),
                              onPressed: isClaimed
                                  ? null
                                  : () => _claimVoucher(v),
                              child: Text(
                                isClaimed ? 'Tersimpan' : 'Klaim',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
