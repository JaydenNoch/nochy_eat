import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:nochy_eat/services/geocoding_service.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/customer_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Layar pelacakan pesanan untuk pembeli.
///
/// Posisi driver datang realtime dari tabel `driver_locations` melalui
/// Supabase Realtime, jadi pembeli bisa melihat apakah driver sedang
/// menuju, sudah sampai, atau pesanan sudah selesai.
class OrderTrackingView extends StatefulWidget {
  const OrderTrackingView({
    super.key,
    required this.orderId,
    required this.storeName,
    required this.storeLatitude,
    required this.storeLongitude,
    required this.deliveryAddress,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.status,
  });

  final String orderId;
  final String storeName;
  final double? storeLatitude;
  final double? storeLongitude;
  final String? deliveryAddress;
  final String? driverId;
  final String? driverName;
  final String? driverPhone;
  final String status;

  @override
  State<OrderTrackingView> createState() => _OrderTrackingViewState();
}

class _OrderTrackingViewState extends State<OrderTrackingView> {
  static const _fallbackCenter = LatLng(-7.7956, 110.3695);

  final SupabaseClient _supabase = Supabase.instance.client;
  final MapController _mapController = MapController();

  LatLng? _driverPos;
  LatLng? _customerPos;
  late LatLng _storePos;

  String _status = '';
  bool _isResolving = true;
  String? _destinationNote;
  double? _driverRating;
  int _driverRatingCount = 0;
  String? _driverAvatarUrl;

  RealtimeChannel? _locationChannel;
  RealtimeChannel? _orderChannel;

  @override
  void initState() {
    super.initState();
    _status = widget.status;
    _storePos = (widget.storeLatitude != null && widget.storeLongitude != null)
        ? LatLng(widget.storeLatitude!, widget.storeLongitude!)
        : _fallbackCenter;

    _bootstrap();
    _subscribeToDriverLocation();
    _subscribeToOrder();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadDriverLocation(), _resolveCustomer()]);
    if (!mounted) return;
    setState(() => _isResolving = false);
    if (_driverPos != null) _fitAll();
  }

  Future<void> _loadDriverLocation() async {
    try {
      final row = await _supabase
          .from('driver_locations')
          .select('latitude, longitude')
          .eq('order_id', widget.orderId)
          .limit(1)
          .maybeSingle();

      final lat = (row?['latitude'] as num?)?.toDouble();
      final lng = (row?['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        setState(() => _driverPos = LatLng(lat, lng));
      }
    } catch (_) {
      // driver belum pernah mengirim posisi
    }
  }

  Future<void> _resolveCustomer() async {
    final customer = await GeocodingService.forward(widget.deliveryAddress ?? '');
    if (!mounted) return;
    setState(() {
      _customerPos = customer;
      _destinationNote = customer == null
          ? 'Alamat tujuan belum bisa ditampilkan di peta.'
          : null;
    });
  }

  Future<void> _loadDriverRating() async {
    if (widget.driverId == null) return;
    try {
      final row = await _supabase
          .from('profiles')
          .select('driver_rating, driver_rating_count, avatar_url')
          .eq('id', widget.driverId!)
          .maybeSingle();

      if (!mounted || row == null) return;
      setState(() {
        _driverRating = (row['driver_rating'] as num?)?.toDouble();
        _driverRatingCount = (row['driver_rating_count'] as num?)?.toInt() ?? 0;
        _driverAvatarUrl = row['avatar_url']?.toString();
      });
    } catch (_) {
      // kolom rating driver mungkin belum dibuat
    }
  }

  /// Dengarkan perubahan posisi driver untuk pesanan ini.
  void _subscribeToDriverLocation() {
    _locationChannel = _supabase
        .channel('tracking-${widget.orderId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'driver_locations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'order_id',
            value: widget.orderId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            final lat = (record['latitude'] as num?)?.toDouble();
            final lng = (record['longitude'] as num?)?.toDouble();
            if (lat == null || lng == null || !mounted) return;

            setState(() => _driverPos = LatLng(lat, lng));

            final zoom = _safeZoom();
            try {
              _mapController.move(LatLng(lat, lng), zoom);
            } catch (_) {}
          },
        )
        .subscribe();
  }

  /// Dengarkan perubahan status pesanan, jadi label berubah sendiri
  /// saat driver menekan "Sampai" atau "Selesai".
  void _subscribeToOrder() {
    _orderChannel = _supabase
        .channel('order-status-${widget.orderId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.orderId,
          ),
          callback: (payload) {
            final newStatus = payload.newRecord['status']?.toString();
            if (newStatus == null || !mounted) return;
            setState(() => _status = newStatus);
          },
        )
        .subscribe();

    _loadDriverRating();
  }

  double _safeZoom() {
    try {
      return _mapController.camera.zoom;
    } catch (_) {
      return 15.0;
    }
  }

  void _fitAll() {
    final points = <LatLng>[
      _storePos,
      if (_customerPos != null) _customerPos!,
      if (_driverPos != null) _driverPos!,
    ];
    final latitudes = points.map((p) => p.latitude).toList();
    final longitudes = points.map((p) => p.longitude).toList();
    final center = LatLng(
      latitudes.reduce((a, b) => a + b) / latitudes.length,
      longitudes.reduce((a, b) => a + b) / longitudes.length,
    );
    try {
      _mapController.move(center, 14.0);
    } catch (_) {}
  }

  Future<void> _callDriver() async {
    final phone = widget.driverPhone?.trim() ?? '';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Driver belum mengisi nomor HP.')),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak bisa membuka aplikasi telepon.')),
      );
    }
  }

  @override
  void dispose() {
    _locationChannel?.unsubscribe();
    _orderChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLightGrey,
      appBar: AppBar(
        backgroundColor: CustomerUi.pinkTint,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        title: const Text(
          'Lacak Pesanan',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
      ),
      body: Column(
        children: [
          _buildStatusBanner(),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _driverPos ?? _storePos,
                    initialZoom: 15.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.nochy_eat',
                    ),
                    MarkerLayer(markers: _buildMarkers()),
                  ],
                ),
                if (_isResolving)
                  const Positioned(
                    top: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: Text(
                            'Menghubungkan ke peta...',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _buildDriverCard(),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    late final String text;
    late final Color color;
    late final IconData icon;

    switch (_status) {
      case 'on_delivery':
        text = 'Driver sedang mengantar pesananmu';
        color = Colors.blue;
        icon = Icons.delivery_dining;
        break;
      case 'arrived':
        text = 'Driver sudah sampai di tempatmu!';
        color = Colors.orange;
        icon = Icons.place;
        break;
      case 'completed':
        text = 'Pesanan selesai. Selamat makan!';
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      default:
        text = 'Menunggu driver mengambil pesanan';
        color = Colors.grey;
        icon = Icons.hourglass_empty;
    }

    return Container(
      width: double.infinity,
       color: CustomerUi.blueTint,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                if (_destinationNote != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _destinationNote!,
                    style: const TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers() {
    return [
      Marker(
        point: _storePos,
        width: 44,
        height: 44,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store, color: AppColors.accentBlue, size: 30),
            Text(
              'Resto',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      if (_customerPos != null)
        Marker(
          point: _customerPos!,
          width: 44,
          height: 44,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flag, color: AppColors.primaryPink, size: 30),
              Text(
                'Alamatmu',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      if (_driverPos != null)
        Marker(
          point: _driverPos!,
          width: 56,
          height: 56,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.two_wheeler, color: Colors.green, size: 32),
              Text(
                'Driver',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _buildDriverCard() {
    final name = widget.driverName ?? 'Driver Nochy';
    final hasDriver = widget.driverId != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: CustomerUi.cardRadius),
        border: Border(top: BorderSide(color: CustomerUi.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            GestureDetector(
              onTap: (_driverAvatarUrl != null && _driverAvatarUrl!.isNotEmpty)
                  ? () => _showPhotoZoom(context, _driverAvatarUrl!)
                  : null,
              child: CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.accentBlue,
                backgroundImage: _driverAvatarUrl != null && _driverAvatarUrl!.isNotEmpty
                    ? NetworkImage(_driverAvatarUrl!)
                    : null,
                child: _driverAvatarUrl == null || _driverAvatarUrl!.isEmpty
                    ? const Icon(Icons.two_wheeler, color: Colors.white, size: 26)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (hasDriver && _driverRating != null)
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 14),
                        const SizedBox(width: 3),
                        Text(
                          '${_driverRating!.toStringAsFixed(1)} · $_driverRatingCount penilaian',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    )
                  else
                    Text(
                      hasDriver
                          ? 'Belum ada penilaian'
                          : 'Belum ada driver yang mengambil pesanan ini',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                ],
              ),
            ),
            if (hasDriver)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryPink,
                  side: const BorderSide(color: AppColors.primaryPink),
                ),
                onPressed: _callDriver,
                icon: const Icon(Icons.phone, size: 16),
                label: const Text(
                  'Hubungi',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPhotoZoom(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: ClipOval(
                    child: Image.network(
                      imageUrl,
                      width: 280,
                      height: 280,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 280,
                        height: 280,
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.person_rounded, size: 80, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 48,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
