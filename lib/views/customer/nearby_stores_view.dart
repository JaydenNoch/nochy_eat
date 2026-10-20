import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:nochy_eat/models/app_models.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/customer_ui.dart';
import 'package:nochy_eat/views/customer/store_detail_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NearbyStoresView extends StatefulWidget {
  final String initialAddress;

  const NearbyStoresView({
    super.key,
    this.initialAddress = 'Jl. Malioboro No. 10, Yogyakarta',
  });

  @override
  State<NearbyStoresView> createState() => _NearbyStoresViewState();
}

class _NearbyStoresViewState extends State<NearbyStoresView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final MapController _mapController = MapController();
  final TextEditingController _addressSearchController = TextEditingController();

  List<StoreModel> _stores = [];
  bool _isLoading = true;
  bool _isSearchingAddress = false;

  // Titik lokasi terpilih
  LatLng _selectedLocation = const LatLng(-7.7956, 110.3695);
  late String _currentAddress;

  @override
  void initState() {
    super.initState();
    _currentAddress = widget.initialAddress;
    _fetchNearbyStores();

    // Jika alamat awal bukan default Malioboro, cari koordinat alamat tersebut
    if (widget.initialAddress != 'Jl. Malioboro No. 10, Yogyakarta') {
      _searchAddressQuietly(widget.initialAddress);
    }
  }

  @override
  void dispose() {
    _addressSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchNearbyStores() async {
    try {
      final response =
      await _supabase.from('stores').select().eq('is_open', true);
      final List<dynamic> data = response;
      setState(() {
        _stores = data.map((json) => StoreModel.fromJson(json)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  /// Sinkronisasi posisi peta dari alamat awal tanpa menampilkan pesan error
  Future<void> _searchAddressQuietly(String query) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=1',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'NochyEatApp/1.0',
      });

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          final newPos = LatLng(lat, lon);

          setState(() {
            _selectedLocation = newPos;
          });

          _mapController.move(newPos, 15.0);
        }
      }
    } catch (_) {}
  }

  /// Reverse Geocoding (Koordinat -> Nama Alamat)
  Future<void> _getAddressFromLatLng(LatLng position) async {
    setState(() {
      _selectedLocation = position;
      _currentAddress = 'Mencari alamat...';
    });

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&zoom=18&addressdetails=1',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'NochyEatApp/1.0',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final displayName = data['display_name'] ?? 'Lokasi Terpilih';

        setState(() {
          _currentAddress = displayName;
        });
      } else {
        setState(() {
          _currentAddress =
          '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        });
      }
    } catch (e) {
      setState(() {
        _currentAddress =
        '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
      });
    }
  }

  /// Forward Geocoding (Nama Alamat -> Koordinat)
  Future<void> _searchAddress(String query) async {
    if (query.trim().isEmpty) return;

    setState(() => _isSearchingAddress = true);
    FocusScope.of(context).unfocus();

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=1',
      );
      final response = await http.get(url, headers: {
        'User-Agent': 'NochyEatApp/1.0',
      });

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          final displayName = data[0]['display_name'];

          final newPos = LatLng(lat, lon);

          setState(() {
            _selectedLocation = newPos;
            _currentAddress = displayName;
          });

          _mapController.move(newPos, 15.0);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alamat tidak ditemukan!')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mencari alamat.')),
      );
    } finally {
      setState(() => _isSearchingAddress = false);
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
          'Resto Sekitarmu',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppColors.textDark,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: AppColors.accentBlue))
          : SafeArea(
        child: RefreshIndicator(
          color: AppColors.accentBlue,
          onRefresh: _fetchNearbyStores,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- 1. SEARCHBAR ALAMAT ---
                Container(
                  decoration: BoxDecoration(
                    color: CustomerUi.blueTint,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.all(CustomerUi.controlRadius),
                      border: Border.all(color: CustomerUi.border),
                    ),
                    child: TextField(
                      controller: _addressSearchController,
                      textInputAction: TextInputAction.search,
                      textAlignVertical: TextAlignVertical.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w500,
                      ),
                      onSubmitted: (value) => _searchAddress(value),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                        prefixIcon: _isSearchingAddress
                            ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accentBlue,
                            ),
                          ),
                        )
                            : IconButton(
                          icon: const Icon(
                            Icons.search_rounded,
                            color: AppColors.accentBlue,
                            size: 20,
                          ),
                          onPressed: () => _searchAddress(
                              _addressSearchController.text),
                        ),
                        hintText:
                        'Cari alamat/wilayah (misal: Sokowetan, Bantul)',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: AppColors.textDark.withValues(alpha: 0.4),
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // --- PETA + SINGLE MARKER MERAH + TOMBOL KUNCI ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(CustomerUi.cardRadius),
                    child: SizedBox(
                      height: 300,
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: _selectedLocation,
                              initialZoom: 15.0,
                              onTap: (tapPosition, point) {
                                _getAddressFromLatLng(point);
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName:
                                'com.example.nochy_eat',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: _selectedLocation,
                                    width: 80,
                                    height: 80,
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(
                                              4),
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(
                                                    alpha: 0.2),
                                                blurRadius: 4,
                                                offset:
                                                const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.location_on_rounded,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Container(
                                          padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.bgWhite,
                                            borderRadius:
                                            BorderRadius.circular(
                                                4),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(
                                                    alpha: 0.1),
                                                blurRadius: 2,
                                              ),
                                            ],
                                          ),
                                          child: const Text(
                                            'Titik Kamu',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.textDark,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          // BANNER ALAMAT & TOMBOL TETAPKAN
                          Positioned(
                            bottom: 12,
                            left: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.bgWhite
                                    .withValues(alpha: 0.98),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.accentBlue
                                              .withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.my_location_rounded,
                                          color: AppColors.accentBlue,
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Lokasi Terpilih (Klik Peta Untuk Ubah)',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: AppColors.textDark
                                                    .withValues(
                                                    alpha: 0.5),
                                                fontWeight:
                                                FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _currentAddress,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight:
                                                FontWeight.bold,
                                                color: AppColors.textDark,
                                              ),
                                              maxLines: 2,
                                              overflow:
                                              TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  // TOMBOL TETAPKAN POSISI
                                  SizedBox(
                                    width: double.infinity,
                                    height: 38,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                        AppColors.accentBlue,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                          BorderRadius.circular(8),
                                        ),
                                        elevation: 0,
                                      ),
                                      onPressed: () {
                                        Navigator.pop(
                                            context, _currentAddress);
                                      },
                                      icon: const Icon(
                                          Icons.check_circle_rounded,
                                          size: 16),
                                      label: const Text(
                                        'Tetapkan Posisi Ini',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
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
                  ),
                ),
                const SizedBox(height: 20),

                // --- DAFTAR RESTO ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rekomendasi Resto Terdekat',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _stores.isEmpty
                          ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(30),
                          child: Text(
                            'Belum ada resto terdekat yang buka.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                          : ListView.builder(
                        shrinkWrap: true,
                        physics:
                        const NeverScrollableScrollPhysics(),
                        itemCount: _stores.length,
                        itemBuilder: (context, index) {
                          final store = _stores[index];
                          return Container(
                            margin:
                            const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: AppColors.bgWhite,
                              borderRadius:
                              BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                      alpha: 0.02),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListTile(
                              contentPadding:
                              const EdgeInsets.all(12),
                              leading: ClipRRect(
                                borderRadius:
                                BorderRadius.circular(8),
                                child: Image.network(
                                  store.imageUrl ??
                                      'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?auto=format&fit=crop&w=300&q=80',
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Container(
                                        width: 60,
                                        height: 60,
                                        color: Colors.grey.shade200,
                                      ),
                                ),
                              ),
                              title: Text(
                                store.storeName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textDark,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    store.address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textDark
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        color: Colors.amber,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${store.rating}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight:
                                          FontWeight.bold,
                                          color: AppColors.textDark,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      const Icon(
                                        Icons.near_me_rounded,
                                        color: AppColors.accentBlue,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      const Text(
                                        '0.8 km • 15 mnt',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight:
                                          FontWeight.w600,
                                          color: AppColors.accentBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.grey.shade400,
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        StoreDetailView(
                                            store: store),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
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
