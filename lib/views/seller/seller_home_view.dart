import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/views/seller/product_form_view.dart';
import 'package:nochy_eat/views/seller/store_form_view.dart';
import 'package:nochy_eat/views/seller/voucher_form_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Halaman utama role Seller / Resto.
///
/// Alur data: satu akun seller memiliki satu toko (`stores.merchant_id`).
/// Pesanan dan menu selalu difilter berdasarkan toko itu, sehingga seller
/// hanya melihat dan mengelola tokonya sendiri.
class SellerHomeView extends StatefulWidget {
  const SellerHomeView({super.key});

  @override
  State<SellerHomeView> createState() => _SellerHomeViewState();
}

class _SellerHomeViewState extends State<SellerHomeView> {
  final SupabaseClient _supabase = Supabase.instance.client;

  int _currentIndex = 0;
  bool _isLoading = true;
  String? _error;

  Map<String, dynamic>? _store;
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _vouchers = [];

  Timer? _orderTimer;

  @override
  void initState() {
    super.initState();
    _loadAll();
    // Segarkan daftar pesanan tiap 15 detik selama halaman terbuka.
    _orderTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _store != null) _fetchOrders(silent: true);
    });
  }

  @override
  void dispose() {
    _orderTimer?.cancel();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Ambil toko milik seller yang login, lalu pesanan & menu toko itu.
  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final store = await _supabase
          .from('stores')
          .select()
          .eq('merchant_id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (store == null) {
        setState(() {
          _store = null;
          _orders = [];
          _products = [];
          _vouchers = [];
          _isLoading = false;
        });
        return;
      }

      setState(() => _store = Map<String, dynamic>.from(store));
      await Future.wait([
        _fetchOrders(silent: true),
        _fetchProducts(silent: true),
        _fetchVouchers(silent: true),
      ]);
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchOrders({bool silent = false}) async {
    if (_store == null) return;
    try {
      final data = await _supabase
          .from('orders')
          .select(
        '*, profiles!orders_customer_id_fkey(full_name, phone), '
            'order_items(quantity, price_at_purchase, products(name)), '
            'stores(store_name)',
      )
          .eq('store_id', _store!['id'])
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() => _orders = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      if (!silent) _snack('Gagal memuat pesanan: $e');
    }
  }

  Future<void> _fetchProducts({bool silent = false}) async {
    if (_store == null) return;
    try {
      final data = await _supabase
          .from('products')
          .select()
          .eq('store_id', _store!['id'])
          .order('name', ascending: true);

      if (!mounted) return;
      setState(() => _products = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      if (!silent) _snack('Gagal memuat menu: $e');
    }
  }

  Future<void> _fetchVouchers({bool silent = false}) async {
    if (_store == null) return;
    try {
      final data = await _supabase
          .from('store_vouchers')
          .select()
          .eq('store_id', _store!['id'])
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() => _vouchers = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      if (!silent) _snack('Gagal memuat voucher: $e');
    }
  }

  Future<void> _setStoreOpen(bool value) async {
    if (_store == null) return;
    try {
      await _supabase.from('stores').update({'is_open': value}).eq('id', _store!['id']);
      if (!mounted) return;
      setState(() => _store!['is_open'] = value);
      _snack(value
          ? 'Toko dibuka. Customer bisa memesan lagi.'
          : 'Toko ditutup. Customer tidak bisa memesan.');
    } catch (e) {
      _snack('Gagal mengubah status toko: $e');
    }
  }

  Future<void> _setStore24Hours(bool value) async {
    if (_store == null) return;
    try {
      await _supabase
          .from('stores')
          .update({'is_24_hours': value}).eq('id', _store!['id']);
      if (!mounted) return;
      setState(() => _store!['is_24_hours'] = value);
      _snack(value
          ? 'Toko muncul di daftar "Buka 24 Jam" customer.'
          : 'Toko dihapus dari daftar "Buka 24 Jam" customer.');
    } catch (e) {
      _snack('Gagal mengubah status 24 jam: $e');
    }
  }

  Future<void> _updateOrderStatus(String orderId, String status) async {
    try {
      await _supabase.from('orders').update({'status': status}).eq('id', orderId);
      await _fetchOrders(silent: true);
    } catch (e) {
      _snack('Gagal memperbarui status pesanan: $e');
    }
  }

  Future<void> _openStoreForm() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => StoreFormView(store: _store)),
    );
    if (changed == true) _loadAll();
  }

  Future<void> _openProductForm([Map<String, dynamic>? product]) async {
    final store = _store;
    if (store == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductFormView(
          storeId: store['id'].toString(),
          product: product,
        ),
      ),
    );
    if (changed == true) _fetchProducts(silent: true);
  }

  Future<void> _confirmDeleteProduct(Map<String, dynamic> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Hapus menu ini?'),
        content: Text('"${product['name']}" akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _supabase.from('products').delete().eq('id', product['id']);
      await _fetchProducts(silent: true);
      _snack('Menu dihapus.');
    } catch (e) {
      _snack('Gagal menghapus menu: $e');
    }
  }

  Future<void> _openVoucherForm([Map<String, dynamic>? voucher]) async {
    final store = _store;
    if (store == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VoucherFormView(
          storeId: store['id'].toString(),
          voucher: voucher,
        ),
      ),
    );
    if (changed == true) _fetchVouchers(silent: true);
  }

  Future<void> _toggleVoucherActive(Map<String, dynamic> voucher) async {
    final next = voucher['is_active'] != true;
    try {
      await _supabase
          .from('store_vouchers')
          .update({'is_active': next}).eq('id', voucher['id']);
      await _fetchVouchers(silent: true);
    } catch (e) {
      _snack('Gagal mengubah voucher: $e');
    }
  }

  Future<void> _confirmDeleteVoucher(Map<String, dynamic> voucher) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Hapus voucher ini?'),
        content: Text('"${voucher['title']}" akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _supabase.from('store_vouchers').delete().eq('id', voucher['id']);
      await _fetchVouchers(silent: true);
      _snack('Voucher dihapus.');
    } catch (e) {
      _snack('Gagal menghapus voucher: $e');
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
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primaryPink.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.storefront, color: AppColors.primaryPink, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'NOCHY NOW',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.primaryPink,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  _store != null ? (_store!['store_name'] ?? 'Role Seller/Restoran') : 'Role Seller/Restoran',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF666666),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: Colors.grey.shade200,
            height: 1.0,
          ),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          elevation: 0,
          backgroundColor: Colors.white,
          onTap: (index) {
            setState(() => _currentIndex = index);
            if (index == 0) _fetchOrders(silent: true);
          },
          selectedItemColor: AppColors.primaryPink,
          unselectedItemColor: Colors.grey.shade600,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 11),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: 'Pesanan'),
            BottomNavigationBarItem(icon: Icon(Icons.fastfood_outlined), activeIcon: Icon(Icons.fastfood), label: 'Menu'),
            BottomNavigationBarItem(icon: Icon(Icons.confirmation_number_outlined), activeIcon: Icon(Icons.confirmation_number), label: 'Voucher'),
            BottomNavigationBarItem(icon: Icon(Icons.storefront_outlined), activeIcon: Icon(Icons.storefront), label: 'Toko'),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryPink));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded, color: Colors.red, size: 36),
              ),
              const SizedBox(height: 16),
              const Text('Gagal Memuat Data Toko', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textDark)),
              const SizedBox(height: 6),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryPink,
                  side: const BorderSide(color: AppColors.primaryPink),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Coba Lagi', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }
    if (_store == null) return _buildNoStoreView();

    switch (_currentIndex) {
      case 0:
        return _buildOrdersTab();
      case 1:
        return _buildProductsTab();
      case 2:
        return _buildVouchersTab();
      default:
        return _buildProfileTab();
    }
  }

  // ===================== BELUM PUNYA TOKO =====================
  Widget _buildNoStoreView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryPink.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.storefront_rounded, size: 56, color: AppColors.primaryPink),
            ),
            const SizedBox(height: 20),
            const Text(
              'Kamu belum punya toko',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark),
            ),
            const SizedBox(height: 8),
            Text(
              'Buat profil toko dulu (nama, alamat, gambar), lalu kamu bisa '
                  'menerima pesanan dan mengelola menu. Toko akan otomatis muncul '
                  'di aplikasi customer.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPink,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _openStoreForm,
                icon: const Icon(Icons.add_business_rounded, size: 20),
                label: const Text('Buat Toko Sekarang', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== TAB 1: PESANAN MASUK =====================
  Widget _buildOrdersTab() {
    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: () => _fetchOrders(silent: true),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pesanan Masuk',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_orders.length} pesanan',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_orders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 80),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'Belum ada pesanan untuk tokomu.',
                    style: TextStyle(color: Color(0xFF666666), fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                ],
              ),
            )
          else
            ..._orders.map(_buildOrderCard),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final status = (order['status'] ?? 'pending').toString();
    final customer = (order['profiles'] as Map?) ?? {};
    final items = (order['order_items'] as List?) ?? [];
    final createdAt = DateTime.tryParse(order['created_at']?.toString() ?? '')?.toLocal();
    final total = (order['total_amount'] as num?)?.toDouble() ??
        (order['total_product_price'] as num?)?.toDouble() ??
        0;
    final isPickup = order['fulfillment_type'] == 'pickup';

    final statusColor = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Kartu
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${order['order_number'] ?? order['id']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (createdAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('dd MMM yyyy • HH:mm').format(createdAt),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (isPickup)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.teal.shade200, width: 0.8),
                        ),
                        child: const Text(
                          'AMBIL SENDIRI',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 0.8),
                      ),
                      child: Text(
                        _statusLabel(status),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),

          // Informasi Pemesan & Alamat
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_outline_rounded, size: 16, color: AppColors.textDark),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${customer['full_name'] ?? 'Pelanggan'} (${customer['phone'] ?? 'tanpa HP'})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        order['delivery_address'] ?? '-',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),

          // Daftar Item Pesanan
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...items.map((item) {
                  final map = item as Map;
                  final product = (map['products'] as Map?) ?? {};
                  final qty = map['quantity'] ?? 0;
                  final price = (map['price_at_purchase'] as num?)?.toDouble() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${qty}x${product['name'] ?? 'Menu'}',
                            style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          'Rp ${(price * (qty as num)).toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textDark),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),

          // Ringkasan Pembayaran & Tombol Aksi
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Pembayaran', style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
                    Text(
                      'Rp ${total.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryPink, fontSize: 15),
                    ),
                  ],
                ),
                ..._buildOrderActions(
                  order['id'].toString(),
                  status,
                  fulfillmentType: order['fulfillment_type']?.toString() ?? 'delivery',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildOrderActions(
      String orderId,
      String status, {
        String fulfillmentType = 'delivery',
      }) {
    final buttons = <Widget>[];

    void add(String label, String newStatus, Color color, {bool isOutlined = false}) {
      buttons.add(
        Expanded(
          child: SizedBox(
            height: 38,
            child: isOutlined
                ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color, width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: EdgeInsets.zero,
              ),
              onPressed: () => _updateOrderStatus(orderId, newStatus),
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            )
                : ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: EdgeInsets.zero,
              ),
              onPressed: () => _updateOrderStatus(orderId, newStatus),
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ),
      );
    }

    switch (status) {
      case 'pending':
        add('Tolak', 'cancelled', Colors.red, isOutlined: true);
        buttons.add(const SizedBox(width: 8));
        add('Terima', 'accepted', AppColors.primaryPink);
        break;
      case 'accepted':
        add('Mulai Masak', 'cooking', AppColors.primaryPink);
        break;
      case 'cooking':
        add('Siap Diambil', 'ready_for_pickup', AppColors.primaryPink);
        break;
    }

    if (buttons.isEmpty) {
      final note = _statusNote(status, fulfillmentType);
      if (note.isEmpty) return [];
      return [
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            note,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }

    return [
      const SizedBox(height: 10),
      Row(children: buttons),
    ];
  }

  // ===================== TAB 2: KELOLA MENU =====================
  Widget _buildProductsTab() {
    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: () => _fetchProducts(silent: true),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Menu Makanan',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPink,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _openProductForm(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Tambah Menu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 80),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.fastfood_outlined, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('Belum ada menu. Tekan "Tambah Menu".', style: TextStyle(color: Color(0xFF666666), fontWeight: FontWeight.w500, fontSize: 14)),
                ],
              ),
            )
          else
            ..._products.map(_buildMenuRow),
        ],
      ),
    );
  }

  Widget _buildMenuRow(Map<String, dynamic> product) {
    final stock = (product['stock'] as num?)?.toInt() ?? 0;
    final price = (product['price'] as num?)?.toDouble() ?? 0;
    final discount = (product['discount_price'] as num?)?.toDouble();
    // Diskon dianggap sah hanya kalau lebih murah dari harga normal,
    // supaya harga coret di daftar menu tidak menyesatkan.
    final hasDiscount = discount != null && discount > 0 && discount < price;
    final effectivePrice = hasDiscount ? discount : price;
    final discountPercent =
        hasDiscount ? ((price - effectivePrice) / price * 100).floor() : 0;
    final image = product['image_url'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: image != null && image.isNotEmpty
                  ? Image.network(
                image,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _imagePlaceholder(),
              )
                  : _imagePlaceholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product['name'] ?? 'Menu',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textDark),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (hasDiscount) ...[
                        Text('Rp ${price.toStringAsFixed(0)}',
                            style: TextStyle(
                                decoration: TextDecoration.lineThrough,
                                fontSize: 11,
                                color: Colors.grey.shade500)),
                        const SizedBox(width: 6),
                      ],
                      Text('Rp ${effectivePrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: AppColors.primaryPink, fontWeight: FontWeight.bold, fontSize: 13)),
                      if (hasDiscount) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primaryPink,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('-$discountPercent%',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stock > 0 ? 'Stok: $stock' : 'Stok habis',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: stock > 0 ? Colors.green.shade700 : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Ubah',
                  icon: const Icon(Icons.edit_outlined, color: AppColors.accentBlue, size: 20),
                  onPressed: () => _openProductForm(product),
                ),
                IconButton(
                  tooltip: 'Hapus',
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                  onPressed: () => _confirmDeleteProduct(product),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 64,
      height: 64,
      color: Colors.grey.shade100,
      child: Icon(Icons.fastfood, color: Colors.grey.shade400, size: 28),
    );
  }

  // ===================== TAB 3: VOUCHER TOKO =====================
  Widget _buildVouchersTab() {
    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: () => _fetchVouchers(silent: true),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Voucher Toko',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textDark)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPink,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _openVoucherForm(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Buat Voucher', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Voucher ini muncul di halaman tokomu dan bisa dipakai pembeli saat checkout.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          if (_vouchers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 80),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.confirmation_number_outlined, size: 56, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('Belum ada voucher. Tekan "Buat Voucher".', style: TextStyle(color: Color(0xFF666666), fontWeight: FontWeight.w500, fontSize: 14)),
                ],
              ),
            )
          else
            ..._vouchers.map(_buildVoucherRow),
        ],
      ),
    );
  }

  Widget _buildVoucherRow(Map<String, dynamic> voucher) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryPink.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.confirmation_number_outlined,
                  color: AppColors.primaryPink, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_voucherHeadline(voucher),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textDark),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(_voucherDetail(voucher),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.highlightYellow.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Kode: ${voucher['code'] ?? '-'}',
                      style: const TextStyle(fontSize: 10, color: AppColors.textDark, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Switch(
                  value: voucher['is_active'] == true,
                  activeColor: Colors.green,
                  onChanged: (_) => _toggleVoucherActive(voucher),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Ubah',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _openVoucherForm(voucher),
                    ),
                    IconButton(
                      tooltip: 'Hapus',
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                      onPressed: () => _confirmDeleteVoucher(voucher),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _voucherHeadline(Map<String, dynamic> v) {
    final type = v['discount_type']?.toString() ?? 'fixed';
    final value = (v['discount_value'] as num?)?.toDouble() ?? 0;
    if (type == 'percent') return 'Diskon ${value.toStringAsFixed(0)}%';
    if (type == 'free_delivery') return 'Gratis Ongkir Rp${value.toStringAsFixed(0)}';
    return 'Potongan Rp${value.toStringAsFixed(0)}';
  }

  String _voucherDetail(Map<String, dynamic> v) {
    final minOrder = (v['min_order'] as num?)?.toDouble() ?? 0;
    final title = v['title']?.toString() ?? '';
    final minLabel = minOrder > 0
        ? 'Min. belanja Rp${minOrder.toStringAsFixed(0)}'
        : 'Tanpa minimum';
    return '$title • $minLabel';
  }

  // ===================== TAB 4: PROFIL TOKO =====================
  Widget _buildProfileTab() {
    final store = _store!;
    final image = store['image_url'] as String?;
    final isOpen = store['is_open'] == true;
    final is24Hours = store['is_24_hours'] == true;
    final rating = (store['rating'] as num?)?.toDouble() ?? 0;
    final ratingCount = (store['rating_count'] as num?)?.toInt() ?? 0;
    final user = _supabase.auth.currentUser;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (image != null && image.isNotEmpty)
                Image.network(
                  image,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storefront_rounded, color: AppColors.primaryPink, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(store['store_name'] ?? 'Toko Saya',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textDark)),
                        ),
                        TextButton.icon(
                          onPressed: _openStoreForm,
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Ubah'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(store['address'] ?? '-',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                        const SizedBox(width: 4),
                        Text(rating.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                        const SizedBox(width: 6),
                        Text(
                          ratingCount > 0
                              ? '($ratingCount penilaian pembeli)'
                              : 'Belum ada penilaian',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: SwitchListTile(
            value: isOpen,
            activeColor: Colors.green,
            onChanged: _setStoreOpen,
            secondary: Icon(
              isOpen ? Icons.store_rounded : Icons.store_outlined,
              color: isOpen ? Colors.green : Colors.grey,
            ),
            title: Text(isOpen ? 'Toko Sedang Buka' : 'Toko Sedang Tutup',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
              isOpen
                  ? 'Customer bisa melihat dan memesan menu.'
                  : 'Menu dan toko disembunyikan dari customer.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: SwitchListTile(
            value: is24Hours,
            activeColor: AppColors.primaryPink,
            onChanged: _setStore24Hours,
            secondary: Icon(
              Icons.access_time_filled_rounded,
              color: is24Hours ? AppColors.primaryPink : Colors.grey,
            ),
            title: const Text('Buka 24 Jam',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
              is24Hours
                  ? 'Toko tampil di daftar "Buka 24 Jam" customer.'
                  : 'Aktifkan agar toko muncul di daftar "Buka 24 Jam".',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Masuk sebagai: ${user?.email ?? '-'}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              await _supabase.auth.signOut();
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Keluar Akun Resto', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  // ===================== HELPERS =====================
  static String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'PESANAN BARU';
      case 'accepted':
        return 'DITERIMA';
      case 'cooking':
        return 'DIMASAK';
      case 'ready_for_pickup':
        return 'SIAP DIAMBIL';
      case 'delivering':
      case 'on_delivery':
        return 'DIANTAR';
      case 'arrived':
        return 'SAMPAI';
      case 'completed':
        return 'SELESAI';
      case 'cancelled':
        return 'DIBATALKAN';
      default:
        return status.toUpperCase();
    }
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange.shade800;
      case 'accepted':
        return AppColors.accentBlue;
      case 'cooking':
        return Colors.deepPurple;
      case 'ready_for_pickup':
        return Colors.teal;
      case 'delivering':
      case 'on_delivery':
        return Colors.blue;
      case 'arrived':
        return Colors.orange.shade800;
      case 'completed':
        return Colors.green.shade700;
      case 'cancelled':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  static String _statusNote(String status, String fulfillmentType) {
    switch (status) {
      case 'ready_for_pickup':
        return fulfillmentType == 'pickup'
            ? 'Menunggu pembeli mengambil pesanan di toko.'
            : 'Menunggu driver mengambil pesanan.';
      case 'delivering':
      case 'on_delivery':
        return 'Pesanan sedang diantar driver.';
      case 'completed':
        return 'Pesanan selesai.';
      case 'cancelled':
        return 'Pesanan dibatalkan.';
      default:
        return '';
    }
  }
}