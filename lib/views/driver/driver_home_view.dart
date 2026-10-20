import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/driver_ui.dart';
import 'package:nochy_eat/views/driver/driver_map_view.dart';
import 'package:nochy_eat/views/driver/driver_profile_edit_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverHomeView extends StatefulWidget {
  const DriverHomeView({super.key});

  @override
  State<DriverHomeView> createState() => _DriverHomeViewState();
}

class _DriverHomeViewState extends State<DriverHomeView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  int _currentIndex = 0;
  bool _isOnline = true;
  bool _isLoading = true;

  List<Map<String, dynamic>> _availableOrders = [];
  List<Map<String, dynamic>> _myOrders = [];
  List<Map<String, dynamic>> _historyOrders = [];

  Map<String, dynamic>? _profile;
  RealtimeChannel? _ordersChannel;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
    _fetchProfile();
    _subscribeToOrders();
  }

  String get _driverId => _supabase.auth.currentUser?.id ?? '';

  /// Orderan siap antar: berstatus ready_for_pickup dan belum diambil driver.
  Future<void> _fetchOrders() async {
    if (_driverId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      const select = '''
        *,
        stores(store_name, address, latitude, longitude),
        customer:profiles!orders_customer_id_fkey(full_name, phone)
      ''';

      final available = await _supabase
          .from('orders')
          .select(select)
          .eq('status', 'ready_for_pickup')
          .isFilter('driver_id', null)
          .order('created_at', ascending: false);

      final mine = await _supabase
          .from('orders')
          .select(select)
          .eq('driver_id', _driverId)
          .inFilter('status', ['on_delivery', 'arrived'])
          .order('created_at', ascending: false);

      final history = await _supabase
          .from('orders')
          .select(select)
          .eq('driver_id', _driverId)
          .eq('status', 'completed')
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        // Pesanan ambil sendiri tidak pernah menyentuh driver, jadi
        // disaring di sini. Disaring di aplikasi, bukan lewat .neq(),
        // supaya daftar orderan tetap jalan walau kolomnya belum ada
        // di database.
        _availableOrders = List<Map<String, dynamic>>.from(available)
            .where((o) => o['fulfillment_type'] != 'pickup')
            .toList();
        _myOrders = List<Map<String, dynamic>>.from(mine);
        _historyOrders = List<Map<String, dynamic>>.from(history);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Fetch orders driver error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchProfile() async {
    if (_driverId.isEmpty) return;
    try {
      final row = await _supabase
          .from('profiles')
          .select('full_name, phone, address, avatar_url, driver_rating, driver_rating_count')
          .eq('id', _driverId)
          .maybeSingle();
      if (mounted) setState(() => _profile = row);
    } catch (e) {
      debugPrint('Fetch profile driver error: $e');
    }
  }

  /// Daftar orderan ikut berubah sendiri saat seller mengubah status
  /// atau saat driver lain mengambil pesanan.
  void _subscribeToOrders() {
    _ordersChannel = _supabase
        .channel('driver-orders-$_driverId')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'orders',
      callback: (_) {
        if (mounted) _fetchOrders();
      },
    )
        .subscribe();
  }

  Future<void> _updateOrder(String orderId, Map<String, dynamic> data) async {
    try {
      await _supabase.from('orders').update(data).eq('id', orderId);
      await _fetchOrders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memperbarui pesanan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _takeOrder(String orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(DriverUi.controlRadius)),
        title: const Text('Ambil pesanan ini?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
          'Pesanan akan menjadi tanggung jawabmu sampai selesai diantar.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPink,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(DriverUi.controlRadius)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, Ambil', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _updateOrder(orderId, {
      'driver_id': _driverId,
      'status': 'on_delivery',
    });
  }

  Future<void> _openMap(Map<String, dynamic> order) async {
    final store = order['stores'] as Map<String, dynamic>? ?? {};

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverMapView(
          orderId: order['id'].toString(),
          storeName: store['store_name']?.toString() ?? 'Resto Nochy',
          storeAddress: store['address']?.toString(),
          storeLatitude: (store['latitude'] as num?)?.toDouble(),
          storeLongitude: (store['longitude'] as num?)?.toDouble(),
          deliveryAddress: order['delivery_address']?.toString(),
          status: order['status']?.toString() ?? 'on_delivery',
        ),
      ),
    );

    // Setelah kembali dari peta, ambil status terbaru dari database.
    await _fetchOrders();
  }

  @override
  void dispose() {
    _ordersChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_buildOrdersTab(), _buildHistoryTab(), _buildProfileTab()];

    return Scaffold(
      backgroundColor: AppColors.bgLightGrey,
      appBar: AppBar(
        backgroundColor: AppColors.primaryPink,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'NOCHY NOW',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  _profile?['full_name']?.toString() ?? 'Panel Driver',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: pages[_currentIndex],
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
            if (index == 0) _fetchOrders();
            setState(() => _currentIndex = index);
          },
          selectedItemColor: AppColors.primaryPink,
          unselectedItemColor: Colors.grey.shade500,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 11),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.two_wheeler_outlined),
              activeIcon: Icon(Icons.two_wheeler),
              label: 'Orderan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: 'Riwayat',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }

  // ===================== TAB 1: ORDERAN =====================
  Widget _buildOrdersTab() {
    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: () async {
        await _fetchOrders();
        await _fetchProfile();
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildOnlineToggle(),
          const SizedBox(height: 16),

          if (!_isOnline)
            _buildNotice(
              icon: Icons.power_settings_new_rounded,
              text: 'Aktifkan status "Siap Narik" untuk menerima orderan.',
            )
          else ...[
            _sectionTitle('Pesanan Milikmu'),
            const SizedBox(height: 10),
            if (_myOrders.isEmpty)
              _buildNotice(
                icon: Icons.local_shipping_outlined,
                text: 'Belum ada pesanan yang kamu ambil.',
              )
            else
              ..._myOrders.map(_buildMyOrderCard),

            const SizedBox(height: 16),
            _sectionTitle('Orderan Tersedia'),
            const SizedBox(height: 10),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: CircularProgressIndicator(color: AppColors.primaryPink),
                ),
              )
            else if (_availableOrders.isEmpty)
              _buildNotice(
                icon: Icons.inbox_outlined,
                text: 'Belum ada pesanan siap antar. Tunggu resto menyiapkan makanan pelanggan.',
              )
            else
              ..._availableOrders.map(_buildAvailableCard),
          ],
        ],
      ),
    );
  }

  Widget _buildOnlineToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _isOnline ? DriverUi.greenTint : Colors.white,
        borderRadius: const BorderRadius.all(DriverUi.controlRadius),
        border: Border.all(
          color: _isOnline ? Colors.green.shade300 : DriverUi.border,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isOnline ? Colors.green.shade600 : Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _isOnline ? 'Status: Siap Narik' : 'Status: Off / Istirahat',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          Switch(
            value: _isOnline,
            activeColor: Colors.green,
            onChanged: (val) => setState(() => _isOnline = val),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: DriverUi.sectionTitle,
    );
  }

  Widget _buildNotice({required IconData icon, required String text}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: DriverUi.surface(),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: DriverUi.mutedText, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderHeader(Map<String, dynamic> order) {
    final status = order['status']?.toString() ?? '';
    final statusLabel = _statusLabel(status);
    final statusColor = _statusColor(status);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '#${order['order_number']?.toString() ?? order['id'].toString().substring(0, 8).toUpperCase()}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
            fontSize: 14,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: const BorderRadius.all(Radius.circular(6)),
            border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 0.8),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaces(Map<String, dynamic> order) {
    final store = order['stores'] as Map<String, dynamic>? ?? {};
    final customer = order['customer'] as Map<String, dynamic>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _placeRow(
          icon: Icons.store_rounded,
          color: AppColors.accentBlue,
          title: store['store_name']?.toString() ?? 'Resto Nochy',
          subtitle: store['address']?.toString() ?? 'Alamat resto',
        ),
        const SizedBox(height: 10),
        _placeRow(
          icon: Icons.location_on_rounded,
          color: AppColors.primaryPink,
          title: customer['full_name']?.toString() ?? 'Pelanggan',
          subtitle: order['delivery_address']?.toString() ?? 'Alamat tujuan',
        ),
      ],
    );
  }

  Widget _placeRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textDark),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFee(Map<String, dynamic> order) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ongkir / Infaq',
          style: TextStyle(fontSize: 11, color: Color(0xFF666666)),
        ),
        Text(
          'Rp ${order['delivery_fee'] ?? 0}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
    bool isOutlined = false,
  }) {
    return SizedBox(
      height: 44,
      width: double.infinity,
      child: isOutlined
          ? OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color, width: 1.2),
          shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(DriverUi.controlRadius)),
          padding: EdgeInsets.zero,
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      )
          : ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(DriverUi.controlRadius)),
          padding: EdgeInsets.zero,
        ),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  /// Pesanan yang sudah diambil: tombol utama membuka peta antar,
  /// lalu driver menandai "sampai" dan "selesai" dari sana.
  Widget _buildMyOrderCard(Map<String, dynamic> order) {
    final status = order['status']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: DriverUi.surface(),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrderHeader(order),
            Divider(height: 20, color: Colors.grey.shade200),
            _buildPlaces(order),
            Divider(height: 20, color: Colors.grey.shade200),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildFee(order),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 140,
                      height: 36,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(DriverUi.controlRadius)),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () => _openMap(order),
                        child: const Text('Buka Peta Antar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (status == 'on_delivery') ...[
              _buildActionButton(
                label: 'Saya Sudah Sampai di Pelanggan',
                color: Colors.orange.shade800,
                onPressed: () => _updateOrder(order['id'], {'status': 'arrived'}),
              ),
              const SizedBox(height: 8),
            ],
            _buildActionButton(
              label: 'Selesaikan Pengantaran',
              color: Colors.green.shade700,
              onPressed: () => _updateOrder(order['id'], {'status': 'completed'}),
            ),
          ],
        ),
      ),
    );
  }

  /// Pesanan yang belum diambil siapa pun.
  Widget _buildAvailableCard(Map<String, dynamic> order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: DriverUi.surface(),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrderHeader(order),
            Divider(height: 20, color: Colors.grey.shade200),
            _buildPlaces(order),
            Divider(height: 20, color: Colors.grey.shade200),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildFee(order),
                SizedBox(
                  width: 120,
                  height: 36,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPink,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(DriverUi.controlRadius)),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => _takeOrder(order['id']),
                    child: const Text('Ambil Pesanan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===================== TAB 2: RIWAYAT =====================
  Widget _buildHistoryTab() {
    return RefreshIndicator(
      color: AppColors.primaryPink,
      onRefresh: _fetchOrders,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          const Text(
            'Riwayat Pengantaran',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          if (_historyOrders.isEmpty)
            _buildNotice(
              icon: Icons.history_rounded,
              text: 'Belum ada riwayat pengantaran selesai.',
            )
          else
            ..._historyOrders.map((h) {
              final store = h['stores'] as Map<String, dynamic>? ?? {};
              final customer = h['customer'] as Map<String, dynamic>? ?? {};

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.all(DriverUi.cardRadius),
                  border: Border.all(color: Colors.grey.shade200, width: 1),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.green, size: 20),
                  ),
                  title: Text(
                    store['store_name']?.toString() ?? 'Resto Nochy',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'Untuk ${customer['full_name']?.toString() ?? 'Pelanggan'}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    '+Rp ${h['delivery_fee'] ?? 0}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.green,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ===================== TAB 3: PROFIL =====================
  Widget _buildProfileTab() {
    final user = _supabase.auth.currentUser;
    final name = _profile?['full_name']?.toString() ?? 'Driver Nochy';
    final phone = _profile?['phone']?.toString() ?? '';
    final rating = (_profile?['driver_rating'] as num?)?.toDouble();
    final ratingCount = (_profile?['driver_rating_count'] as num?)?.toInt() ?? 0;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.all(DriverUi.cardRadius),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.primaryPink,
                  backgroundImage: _profile?['avatar_url'] != null && _profile!['avatar_url'].toString().isNotEmpty
                      ? NetworkImage(_profile!['avatar_url'].toString())
                      : null,
                  child: _profile?['avatar_url'] == null || _profile!['avatar_url'].toString().isEmpty
                      ? const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 28)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppColors.textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        user?.email ?? 'driver@nochy.com',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        phone.isEmpty ? 'Nomor HP belum diisi' : phone,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.all(DriverUi.cardRadius),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rating Driver',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      rating == null ? '0.0' : rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: Colors.amber,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: List.generate(5, (i) {
                        final filled = rating != null && i < rating.round();
                        return Icon(
                          filled ? Icons.star_rounded : Icons.star_border_rounded,
                          color: Colors.amber,
                          size: 16,
                        );
                      }),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '($ratingCount penilaian)',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Rating ini adalah rata-rata seluruh penilaian dari pembeli yang kamu antar.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPink,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(DriverUi.controlRadius),
              ),
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DriverProfileEditView()),
              );
              _fetchProfile();
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text(
              'Edit Profil Driver',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(DriverUi.controlRadius),
              ),
            ),
            onPressed: () async {
              await _supabase.auth.signOut();
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('Keluar Akun Driver', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  // ===================== HELPERS =====================
  static String _statusLabel(String status) {
    switch (status) {
      case 'ready_for_pickup':
        return 'SIAP DIAMBIL';
      case 'on_delivery':
        return 'SEDANG DIANTAR';
      case 'arrived':
        return 'SAMPAI DI PELANGGAN';
      case 'completed':
        return 'SELESAI';
      default:
        return status.toUpperCase();
    }
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'ready_for_pickup':
        return Colors.orange.shade800;
      case 'on_delivery':
        return Colors.blue;
      case 'arrived':
        return Colors.deepPurple;
      case 'completed':
        return Colors.green.shade700;
      default:
        return Colors.grey.shade700;
    }
  }
}