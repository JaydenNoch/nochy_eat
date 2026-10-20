import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:nochy_eat/theme/app_colors.dart';

/// Peta pemilih lokasi.
///
/// Mengembalikan `Map<String, dynamic>` berisi:
/// `address` (String), `latitude` (double), `longitude` (double).
class LocationPickerView extends StatefulWidget {
  final double initialLatitude;
  final double initialLongitude;

  const LocationPickerView({
    super.key,
    this.initialLatitude = -7.7956,
    this.initialLongitude = 110.3695,
  });

  @override
  State<LocationPickerView> createState() => _LocationPickerViewState();
}

class _LocationPickerViewState extends State<LocationPickerView> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  late LatLng _selected;
  String _address = '';
  bool _isSearching = false;
  bool _isResolving = false;

  @override
  void initState() {
    super.initState();
    _selected = LatLng(widget.initialLatitude, widget.initialLongitude);
    _reverseGeocode(_selected);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String> _reverseGeocode(LatLng position) async {
    setState(() => _isResolving = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&zoom=18&addressdetails=1',
      );
      final response = await http.get(url, headers: {'User-Agent': 'NochyEatApp/1.0'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.isNotEmpty) {
          setState(() => _address = displayName);
          return displayName;
        }
      }
    } catch (_) {
      // jatuh ke fallback di bawah
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
    final fallback =
        '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
    if (mounted) setState(() => _address = fallback);
    return fallback;
  }

  Future<void> _searchAddress(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);
    FocusScope.of(context).unfocus();
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=1',
      );
      final response = await http.get(url, headers: {'User-Agent': 'NochyEatApp/1.0'});
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          final newPos = LatLng(lat, lon);
          setState(() {
            _selected = newPos;
            _address = data[0]['display_name'] ?? _address;
          });
          _mapController.move(newPos, 16.0);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lokasi tidak ditemukan.')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mencari lokasi.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLightGrey,
      appBar: AppBar(
        backgroundColor: AppColors.primaryPink,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Pilih Lokasi Toko 📍',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.primaryPink,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.bgWhite,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                onSubmitted: _searchAddress,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  prefixIcon: _isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primaryPink,
                            ),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.search, color: AppColors.primaryPink, size: 22),
                          onPressed: () => _searchAddress(_searchController.text),
                        ),
                  hintText: 'Cari nama jalan / daerah toko',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selected,
                    initialZoom: 16.0,
                    onTap: (_, point) {
                      setState(() => _selected = point);
                      _reverseGeocode(point);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.nochy_eat',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _selected,
                          width: 80,
                          height: 80,
                          child: const Icon(
                            Icons.location_on,
                            color: AppColors.primaryPink,
                            size: 44,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgWhite,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ketuk peta untuk memindah titik',
                          style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (_isResolving)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            if (_isResolving) const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _address.isEmpty ? 'Menentukan alamat...' : _address,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 40,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryPink,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            onPressed: () async {
                              final address =
                                  _address.isEmpty ? await _reverseGeocode(_selected) : _address;
                              if (!context.mounted) return;
                              Navigator.pop(context, {
                                'address': address,
                                'latitude': _selected.latitude,
                                'longitude': _selected.longitude,
                              });
                            },
                            icon: const Icon(Icons.check_circle, size: 18),
                            label: const Text(
                              'Gunakan Lokasi Ini',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
