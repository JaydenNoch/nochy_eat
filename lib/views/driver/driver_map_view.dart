import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:nochy_eat/services/geocoding_service.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/driver_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Peta pengantaran untuk driver.
///
/// Karena ini aplikasi percobaan, posisi driver digerakkan manual oleh
/// driver sendiri (geser marker). Setiap posisi dikirim ke tabel
/// `driver_locations`, dan pembeli melihatnya secara realtime lewat
/// [OrderTrackingView].
class DriverMapView extends StatefulWidget {
  const DriverMapView({
    super.key,
    required this.orderId,
    required this.storeName,
    required this.storeAddress,
    required this.storeLatitude,
    required this.storeLongitude,
    required this.deliveryAddress,
    required this.status,
  });

  final String orderId;
  final String storeName;
  final String? storeAddress;
  final double? storeLatitude;
  final double? storeLongitude;
  final String? deliveryAddress;
  final String status;

  @override
  State<DriverMapView> createState() => _DriverMapViewState();
}

class _DriverMapViewState extends State<DriverMapView> {
  static const _fallbackCenter = LatLng(-7.7956, 110.3695);

  final SupabaseClient _supabase = Supabase.instance.client;
  final MapController _mapController = MapController();

  late LatLng _driverPos;
  LatLng? _customerPos;
  LatLng? _storePos;

  bool _isSending = false;
  bool _isResolving = true;
  String? _destinationNote;
  bool _autoMove = false;
  Timer? _autoTimer;
  String? _lastSentAt;

  @override
  void initState() {
    super.initState();
    _storePos = (widget.storeLatitude != null && widget.storeLongitude != null)
        ? LatLng(widget.storeLatitude!, widget.storeLongitude!)
        : null;
    _driverPos = _storePos ?? _fallbackCenter;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadExistingLocation(), _resolveCustomer()]);
    if (!mounted) return;
    setState(() => _isResolving = false);

    if (_storePos != null) {
      _fitAll();
    }
  }

  /// Ambil posisi terakhir yang tersimpan supaya peta tidak melompat
  /// setiap kali layar dibuka. Satu pesanan punya satu baris posisi.
  Future<void> _loadExistingLocation() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final row = await _supabase
          .from('driver_locations')
          .select('latitude, longitude')
          .eq('driver_id', user.id)
          .eq('order_id', widget.orderId)
          .limit(1)
          .maybeSingle();

      final lat = (row?['latitude'] as num?)?.toDouble();
      final lng = (row?['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        setState(() => _driverPos = LatLng(lat, lng));
      }
    } catch (_) {
      // posisi lama tidak wajib ada
    }
  }

  /// Alamat pesanan disimpan sebagai teks, jadi dijadikan koordinat
  /// dulu supaya driver punya marker tujuan.
  Future<void> _resolveCustomer() async {
    final customer = await GeocodingService.forward(widget.deliveryAddress ?? '');
    if (!mounted) return;
    setState(() {
      _customerPos = customer;
      _destinationNote = customer == null
          ? 'Lokasi tujuan tidak ditemukan di peta. Geser marker manual.'
          : null;
    });
  }

  void _fitAll() {
    final points = <LatLng>[
      if (_storePos != null) _storePos!,
      if (_customerPos != null) _customerPos!,
      _driverPos,
    ];
    if (points.isEmpty) return;

    final latitudes = points.map((p) => p.latitude).toList();
    final longitudes = points.map((p) => p.longitude).toList();
    final center = LatLng(
      (latitudes.reduce((a, b) => a + b)) / latitudes.length,
      (longitudes.reduce((a, b) => a + b)) / longitudes.length,
    );
    try {
      _mapController.move(center, 14.0);
    } catch (_) {
      // controller belum terpasang
    }
  }

  Future<void> _sendPosition([LatLng? position, bool notify = true]) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final pos = position ?? _driverPos;

    setState(() => _isSending = true);
    try {
      final payload = {
        'driver_id': user.id,
        'order_id': widget.orderId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final existing = await _supabase
          .from('driver_locations')
          .select('id')
          .eq('driver_id', user.id)
          .eq('order_id', widget.orderId)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        await _supabase
            .from('driver_locations')
            .update(payload)
            .eq('id', existing['id']);
      } else {
        await _supabase.from('driver_locations').insert(payload);
      }

      if (!mounted) return;
      setState(() {
        _lastSentAt = TimeOfDay.now().format(context);
      });

      if (!notify) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Posisi terkirim ke pelanggan 🛵'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengirim posisi: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _toggleAutoMove(bool enabled) {
    setState(() => _autoMove = enabled);
    _autoTimer?.cancel();

    if (!enabled) return;

    _autoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_autoMove) return;

      final target = _customerPos ?? _storePos;
      if (target == null) return;

      // Maju 20% dari jarak yang tersisa tiap langkah, jadi terlihat
      // bergerak seperti pengantaran sungguhan.
      setState(() {
        _driverPos = LatLng(
          _driverPos.latitude + (target.latitude - _driverPos.latitude) * 0.2,
          _driverPos.longitude + (target.longitude - _driverPos.longitude) * 0.2,
        );
      });

      try {
        _mapController.move(_driverPos, _mapController.camera.zoom);
      } catch (_) {}

      _sendPosition(_driverPos, false);
    });
  }

  Future<void> _updateStatus(String newStatus) async {
    try {
      await _supabase
          .from('orders')
          .update({'status': newStatus})
          .eq('id', widget.orderId);

      if (!mounted) return;
      Navigator.pop(context, newStatus);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memperbarui status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLightGrey,
      appBar: AppBar(
        backgroundColor: AppColors.primaryPink,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Peta Antar ${widget.storeName}',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _driverPos,
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
                            'Mencari lokasi tujuan...',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _buildControlPanel(),
        ],
      ),
    );
  }

  /// flutter_map 7 tidak lagi menyediakan marker draggable, jadi
  /// geserannya dihitung sendiri: offset jari dikonversi dari satuan
  /// piksel layar ke derajat memakai proyeksi Mercator.
  void _onDriverDrag(DragUpdateDetails details) {
    double zoom;
    try {
      zoom = _mapController.camera.zoom;
    } catch (_) {
      return;
    }

    final worldPixels = 256.0 * pow(2.0, zoom);
    final lngPerPixel = 360.0 / worldPixels;
    final latPerPixel =
        360.0 * cos(_driverPos.latitude * pi / 180.0) / worldPixels;

    setState(() {
      _driverPos = LatLng(
        (_driverPos.latitude - details.delta.dy * latPerPixel)
            .clamp(-85.0, 85.0),
        _driverPos.longitude + details.delta.dx * lngPerPixel,
      );
    });
  }

  List<Marker> _buildMarkers() {
    return [
      if (_storePos != null)
        Marker(
          point: _storePos!,
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
                'Pelanggan',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      Marker(
        point: _driverPos,
        width: 56,
        height: 56,
        child: GestureDetector(
          onPanUpdate: _onDriverDrag,
          onPanEnd: (_) => _sendPosition(),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.two_wheeler, color: Colors.green, size: 32),
              Text(
                'Geser saya',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildControlPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: AppColors.bgWhite,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Colors.grey.shade200, blurRadius: 8, spreadRadius: 2),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.deliveryAddress?.isNotEmpty == true
                  ? widget.deliveryAddress!
                  : 'Alamat tujuan belum diisi',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (_destinationNote != null) ...[
              const SizedBox(height: 6),
              Text(
                _destinationNote!,
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ],
            if (_lastSentAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'Posisi terakhir dikirim: $_lastSentAt',
                style: const TextStyle(fontSize: 11, color: Colors.green),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPink,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: const BorderRadius.all(DriverUi.controlRadius),
                      ),
                    ),
                    onPressed: _isSending ? null : () => _sendPosition(),
                    icon: const Icon(Icons.my_location, size: 16),
                    label: const Text(
                      'Kirim Posisi',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _autoMove,
                    activeThumbColor: Colors.green,
                    title: const Text(
                      'Simulasi',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    onChanged: _customerPos == null && _storePos == null
                        ? null
                        : _toggleAutoMove,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (widget.status == 'on_delivery')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: const BorderRadius.all(DriverUi.controlRadius),
                    ),
                  ),
                  onPressed: () => _updateStatus('arrived'),
                  child: const Text(
                    'Saya Sudah Sampai di Pelanggan',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            if (widget.status == 'arrived')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: const BorderRadius.all(DriverUi.controlRadius),
                    ),
                  ),
                  onPressed: () => _updateStatus('completed'),
                  child: const Text(
                    'Selesaikan Pengantaran',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
