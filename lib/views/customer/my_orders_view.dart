import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nochy_eat/models/app_models.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/customer_ui.dart';
import 'package:nochy_eat/views/customer/order_tracking_view.dart';
import 'package:nochy_eat/views/customer/store_detail_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class MyOrdersView extends StatefulWidget {
  const MyOrdersView({super.key, this.refreshToken = 0});

  /// Dinaikkan layar induk setiap tab "Pesanan Saya" dipilih atau user login.
  /// Widget ini hidup di IndexedStack, jadi initState hanya jalan sekali.
  final int refreshToken;

  @override
  State<MyOrdersView> createState() => _MyOrdersViewState();
}

class _MyOrdersViewState extends State<MyOrdersView> with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  late TabController _tabController;
  List<OrderModel> _activeOrders = [];
  List<OrderModel> _pastOrders = [];

  /// Rating yang sudah dikirim pembeli ini, kunci = order_id.
  Map<String, Map<String, dynamic>> _myRatings = {};
  bool _isLoading = true;
  String? _error;

  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchOrders();

    // Sesi Supabase bisa baru pulih beberapa detik setelah layar dibuka.
    // Saat app dibuka dengan sesi tersimpan, eventnya `initialSession`,
    // bukan `signedIn` — keduanya harus ditangkap.
    _authSub = _supabase.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.signedOut ||
          state.event == AuthChangeEvent.initialSession) {
        _fetchOrders();
      }
    });
  }

  @override
  void didUpdateWidget(covariant MyOrdersView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      // Ditunda satu frame: panggilan ini terjadi saat fase build,
      // setState tidak boleh dipanggil dari situ.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchOrders();
      });
    }
  }

  Future<void> _fetchOrders() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _activeOrders = [];
          _pastOrders = [];
          _myRatings = {};
          _error = null;
          _isLoading = false;
        });
        return;
      }

      final response = await _supabase
          .from('orders')
          .select('''
            *,
            stores(store_name, latitude, longitude),
            driver:profiles!orders_driver_id_fkey(full_name, phone)
          ''')
          .eq('customer_id', user.id)
          .order('created_at', ascending: false);

      final List<dynamic> data = response;
      final allOrders = data.map((json) => OrderModel.fromJson(json)).toList();

      Map<String, Map<String, dynamic>> ratings = {};
      try {
        final ratingRows = await _supabase
            .from('ratings')
            .select()
            .eq('customer_id', user.id);
        for (final row in ratingRows as List) {
          final map = Map<String, dynamic>.from(row);
          final orderId = map['order_id']?.toString();
          if (orderId == null) continue;

          // Satu pesanan bisa punya lebih dari satu baris rating
          // (toko dan driver). Digabung supaya tombol penilaian tidak
          // muncul lagi untuk yang sudah dinilai.
          final previous = ratings[orderId];
          ratings[orderId] = previous == null
              ? map
              : {
            ...previous,
            ...Map.fromEntries(
              map.entries.where((entry) => entry.value != null),
            ),
          };
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _activeOrders = allOrders
            .where((o) => o.status != 'completed' && o.status != 'cancelled')
            .toList();
        _pastOrders = allOrders
            .where((o) => o.status == 'completed' || o.status == 'cancelled')
            .toList();
        _myRatings = ratings;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Fetch orders error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Kirim penilaian pembeli untuk toko. Rating toko yang tampil di
  /// semua pembeli adalah rata-rata seluruh penilaian ini.
  Future<void> _submitStoreRating(OrderModel order, int stars, String review) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Satu pesanan bisa sudah punya baris rating (misal pembeli sudah
      // menilai drivernya dulu). Kalau barisnya ada, rating toko ditulis
      // ke baris yang sama supaya tidak dobel dan tidak bentrok
      // unique constraint kalau tabel itu punya satu.
      final existing = _myRatings[order.id];
      Map<String, dynamic>? inserted;

      if (existing?['id'] != null) {
        inserted = await _supabase
            .from('ratings')
            .update({
          'store_rating': stars,
          'review_text': review.isEmpty ? null : review,
        })
            .eq('id', existing!['id'])
            .select()
            .maybeSingle();
      } else {
        inserted = await _supabase.from('ratings').insert({
          'order_id': order.id,
          'customer_id': user.id,
          'store_id': order.storeId,
          'store_rating': stars,
          'review_text': review.isEmpty ? null : review,
        }).select().maybeSingle();
      }

      await _supabase.rpc(
        'refresh_store_rating',
        params: {'p_store_id': order.storeId},
      );

      if (!mounted) return;
      setState(() {
        _myRatings[order.id] = inserted ??
            {'order_id': order.id, 'store_rating': stars, 'review_text': review};
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Terima kasih, penilaianmu terkirim ⭐')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim penilaian: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Kirim penilaian pembeli untuk driver. Rata-rata seluruh penilaian
  /// inilah yang tampil di profil driver dan di layar pelacakan.
  Future<void> _submitDriverRating(OrderModel order, int stars) async {
    final user = _supabase.auth.currentUser;
    final driverId = order.driverId;
    if (user == null || driverId == null) return;

    try {
      // Satu pesanan punya satu baris rating. Kalau pembeli sudah
      // menilai tokonya, rating driver ditulis ke baris yang sama.
      final existing = _myRatings[order.id];
      Map<String, dynamic>? saved;

      if (existing?['id'] != null) {
        saved = await _supabase
            .from('ratings')
            .update({'driver_rating': stars})
            .eq('id', existing!['id'])
            .select()
            .maybeSingle();
      } else {
        saved = await _supabase.from('ratings').insert({
          'order_id': order.id,
          'customer_id': user.id,
          'store_id': order.storeId,
          'driver_rating': stars,
        }).select().maybeSingle();
      }

      await _supabase.rpc(
        'refresh_driver_rating',
        params: {'p_driver_id': driverId},
      );

      if (!mounted) return;
      setState(() {
        _myRatings[order.id] = saved ??
            {'order_id': order.id, 'driver_rating': stars};
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Terima kasih, penilaian driver terkirim 🛵')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengirim penilaian driver: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showRatingSheet(OrderModel order) {
    int stars = 5;
    final reviewController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Beri Penilaian ${order.storeName ?? 'Toko'}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Penilaianmu dihitung jadi rata-rata rating toko.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) {
                    final filled = i < stars;
                    return IconButton(
                      onPressed: () => setSheet(() => stars = i + 1),
                      icon: Icon(
                        filled ? Icons.star_rounded : Icons.star_border_rounded,
                        color: Colors.amber,
                        size: 38,
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reviewController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Tulis ulasan (opsional)',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.bgLightGrey,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    final review = reviewController.text.trim();
                    Navigator.pop(sheetCtx);
                    reviewController.dispose();
                    _submitStoreRating(order, stars, review);
                  },
                  child: const Text('Kirim Penilaian',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDriverRatingSheet(OrderModel order) {
    int stars = 5;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Beri Penilaian Driver 🛵',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Dinilai: ${order.driverName ?? 'Driver yang mengantar'}',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              const Text(
                'Penilaianmu dihitung jadi rata-rata rating driver tersebut.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) {
                    final filled = i < stars;
                    return IconButton(
                      onPressed: () => setSheet(() => stars = i + 1),
                      icon: Icon(
                        filled ? Icons.star_rounded : Icons.star_border_rounded,
                        color: Colors.amber,
                        size: 38,
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    _submitDriverRating(order, stars);
                  },
                  child: const Text(
                    'Kirim Penilaian',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Buka layar pelacakan realtime untuk pesanan yang sudah punya driver.
  void _openTracking(OrderModel order) {
    if (order.driverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Belum ada driver yang mengambil pesanan ini.'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderTrackingView(
          orderId: order.id,
          storeName: order.storeName ?? 'Resto Nochy',
          storeLatitude: order.storeLatitude,
          storeLongitude: order.storeLongitude,
          deliveryAddress: order.deliveryAddress,
          driverId: order.driverId,
          driverName: order.driverName,
          driverPhone: order.driverPhone,
          status: order.status,
        ),
      ),
    ).then((_) {
      // Status berubah di layar pelacakan, muat ulang daftar pesanan.
      if (mounted) _fetchOrders();
    });
  }

  /// Tombol utama pada kartu pesanan, mengikuti tipe pesanan dan statusnya.
  String _actionLabel(
      OrderModel order, {
        required bool isActive,
        required bool pickupWaiting,
      }) {
    if (!isActive) return 'Pesan Lagi';

    if (order.isPickup) {
      if (pickupWaiting) return 'Menunggu Disiapkan 🍳';
      if (order.status == 'ready_for_pickup') return 'Sudah Saya Ambil 🛍️';
      return 'Pesan Lagi';
    }

    return order.driverId != null ? 'Lacak Pesanan Live 🛵' : 'Lacak Pesanan 🛵';
  }

  /// Menutup pesanan ambil sendiri begitu pembeli benar-benar menerima
  /// makanannya di toko. Tidak ada driver sama sekali, jadi statusnya
  /// langsung selesai tanpa melewati on_delivery/arrived.
  Future<void> _confirmPickup(OrderModel order) async {
    try {
      final updated = await _supabase
          .from('orders')
          .update({'status': 'completed'})
          .eq('id', order.id)
      // Kondisi status ikut dicocokkan supaya percobaan kedua tidak
      // menimpa pesanan yang sudah berubah oleh pihak lain.
          .eq('status', 'ready_for_pickup')
          .select('id');

      // Supabase diam-diam mengembalikan 0 baris kalau RLS menolak,
      // jadi diperiksa dulu sebelum dianggap berhasil.
      if (updated.isEmpty) {
        throw Exception('pesanan sudah berubah, coba muat ulang');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Terima kasih! Pesanan kamu sudah selesai 🍽️'),
        ),
      );
      await _fetchOrders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menutup pesanan: $e')),
      );
    }
  }

  /// Buka halaman toko dengan keranjang yang sudah diisi item dari
  /// pesanan sebelumnya, sehingga user tinggal checkout langsung.
  Future<void> _pesanLagi(OrderModel order) async {
    // Tampilkan loading dulu
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Membuka toko...'),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      // 1. Fetch data toko
      final storeData = await _supabase
          .from('stores')
          .select()
          .eq('id', order.storeId)
          .maybeSingle();

      if (storeData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Toko tidak ditemukan atau sudah tutup permanen.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final store = StoreModel.fromJson(storeData);

      // 2. Fetch order_items dari pesanan ini
      final itemsData = await _supabase
          .from('order_items')
          .select('product_id, quantity')
          .eq('order_id', order.id);

      final Map<String, int> initialCart = {};
      for (final item in itemsData as List) {
        final pid = item['product_id']?.toString();
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        if (pid != null) initialCart[pid] = qty;
      }

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoreDetailView(
            store: store,
            initialCart: initialCart,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal membuka toko: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  String _getStatusLabel(OrderModel order) {
    final status = order.status;
    switch (status) {
      case 'pending':
        return 'Menunggu Konfirmasi Resto';
      case 'accepted':
      case 'cooking':
        return 'Makanan Sedang Dimasak';
      case 'ready_for_pickup':
      // Di sini driver menunggu pesanan antar, sementara pesanan
      // ambil sendiri menunggu pembeli datang ke toko.
        return order.isPickup ? 'Siap Diambil di Toko' : 'Menunggu Driver';
      case 'delivering':
      case 'on_delivery':
        return 'Driver Sedang Mengantar';
      case 'arrived':
        return 'Driver Sudah Sampai';
      case 'completed':
        return 'Pesanan Selesai';
      case 'cancelled':
        return 'Pesanan Dibatalkan';
      default:
        return 'Memproses Pesanan';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red.shade700;
      case 'arrived':
        return Colors.orange.shade800;
      case 'on_delivery':
      case 'delivering':
        return AppColors.accentBlue;
      default:
        return AppColors.primaryPink;
    }
  }

  /// Bagian penilaian untuk pesanan yang sudah selesai.
  /// Satu pesanan bisa dinilai dua kali: tokonya dan drivernya.
  Widget _buildRatingSection(OrderModel order) {
    final existing = _myRatings[order.id];
    final storeStars = (existing?['store_rating'] as num?)?.toInt();
    final driverStars = (existing?['driver_rating'] as num?)?.toInt();
    final canRateDriver = order.driverId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        storeStars == null
            ? _ratingPromptButton(
          label: 'Beri Penilaian Toko ⭐',
          onPressed: () => _showRatingSheet(order),
        )
            : _ratedBox(
          caption: 'Penilaian tokomu:',
          stars: storeStars,
          review: existing?['review_text']?.toString(),
        ),
        if (canRateDriver) ...[
          const SizedBox(height: 10),
          driverStars == null
              ? _ratingPromptButton(
            label: 'Beri Penilaian Driver 🛵',
            onPressed: () => _showDriverRatingSheet(order),
          )
              : _ratedBox(
            caption: 'Penilaian driver:',
            stars: driverStars,
            review: null,
          ),
        ],
      ],
    );
  }

  Widget _ratingPromptButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryPink,
          side: const BorderSide(color: AppColors.primaryPink, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.star_border_rounded, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }

  Widget _ratedBox({
    required String caption,
    required int stars,
    String? review,
  }) {
    final reviewText = review ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(caption,
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
              const Spacer(),
              ...List.generate(
                5,
                    (i) => Icon(
                  i < stars ? Icons.star_rounded : Icons.star_border_rounded,
                  color: Colors.amber,
                  size: 16,
                ),
              ),
            ],
          ),
          if (reviewText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(reviewText,
                style: const TextStyle(fontSize: 12, color: AppColors.textDark, height: 1.3)),
          ],
        ],
      ),
    );
  }

  /// Akun yang sedang dipakai. Kalau daftar pesanan kosong, cepat ketahuan
  /// apakah karena login bukan dengan akun yang tadi memesan.
  String _accountLabel() {
    final user = _supabase.auth.currentUser;
    if (user == null) return 'Belum login — buka tab "Saya" untuk masuk.';
    return 'Login sebagai: ${user.email ?? '(tanpa email)'}\n'
        'ID: ${user.id}';
  }

  /// Isi tab saat daftar kosong: tampilkan error gagal muat lebih dulu,
  /// baru pesan "belum ada pesanan".
  Widget _buildEmptyState(bool isActive) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.red),
              ),
              const SizedBox(height: 16),
              const Text(
                'Gagal memuat pesanan',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _fetchOrders,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Coba lagi',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primaryPink.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isActive ? Icons.receipt_long_rounded : Icons.history_rounded,
                size: 56,
                color: AppColors.primaryPink.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isActive ? 'Belum ada pesanan aktif' : 'Belum ada riwayat pesanan',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tarik ke bawah untuk memperbarui',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgWhite,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                _accountLabel(),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11, height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderList(List<OrderModel> orders, {required bool isActive}) {
    if (orders.isEmpty) {
      // Harus tetap bisa di-scroll, kalau tidak RefreshIndicator tidak
      // bisa ditarik dan pesanan baru tak bisa dimuat ulang.
      return RefreshIndicator(
        color: AppColors.primaryPink,
        onRefresh: _fetchOrders,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: _buildEmptyState(isActive),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: _fetchOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          final statusColor = _getStatusColor(order.status);

          // Pesanan ambil sendiri hanya bisa ditutup pembeli setelah
          // sellernya menandai pesanan siap diambil; sebelum itu tidak
          // ada yang bisa dilakukan pembeli selain menunggu.
          final bool pickupWaiting =
              isActive && order.isPickup && order.status != 'ready_for_pickup';

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: CustomerUi.surface(),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(CustomerUi.cardRadius),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bagian Header Kartu (Resto & Status Badge)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: CustomerUi.pinkTint,
                      border: const Border(bottom: BorderSide(color: CustomerUi.border)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryPink.withValues(alpha: 0.1),
                                borderRadius: const BorderRadius.all(CustomerUi.controlRadius),
                                ),
                                child: const Icon(
                                  Icons.store_rounded,
                                  color: AppColors.primaryPink,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  order.storeName ?? 'Toko',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.textDark,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: const BorderRadius.all(Radius.circular(6)),
                          ),
                          child: Text(
                            _getStatusLabel(order),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bagian Isi (Detail Pembayaran & Informasi)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Pembayaran',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Rp ${order.totalAmount.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: AppColors.primaryPink,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Metode Pembayaran',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    order.paymentMethod.toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Tombol Aksi Utama
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isActive && !pickupWaiting
                                  ? AppColors.primaryPink
                                  : AppColors.bgLightGrey,
                              foregroundColor:
                              isActive && !pickupWaiting ? Colors.white : AppColors.textDark,
                              elevation: 0,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(CustomerUi.controlRadius),
                              ),
                            ),
                            onPressed: pickupWaiting
                                ? null
                                : () {
                              if (!isActive) {
                                _pesanLagi(order);
                                return;
                              }
                              if (order.isPickup) {
                                if (order.status == 'ready_for_pickup') {
                                  _confirmPickup(order);
                                }
                                return;
                              }
                              _openTracking(order);
                            },
                            child: Text(
                              _actionLabel(order, isActive: isActive, pickupWaiting: pickupWaiting),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ),

                        // Bagian Rating / Penilaian (jika pesanan selesai)
                        if (!isActive && order.status == 'completed') ...[
                          const SizedBox(height: 14),
                          const Divider(height: 1, color: Color(0xFFEEEEEE)),
                          const SizedBox(height: 14),
                          _buildRatingSection(order),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLightGrey,
      appBar: AppBar(
        backgroundColor: CustomerUi.pinkTint,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: const Text(
          'Pesanan Saya',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              color: CustomerUi.pinkTint,
              border: const Border(bottom: BorderSide(color: CustomerUi.border)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primaryPink,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.primaryPink,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              tabs: const [
                Tab(text: 'Dalam Proses'),
                Tab(text: 'Riwayat Selesai'),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryPink))
          : TabBarView(
        controller: _tabController,
        children: [
          _buildOrderList(_activeOrders, isActive: true),
          _buildOrderList(_pastOrders, isActive: false),
        ],
      ),
    );
  }
}
