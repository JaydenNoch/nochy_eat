import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:nochy_eat/models/app_models.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/customer_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class StoreHeader extends StatelessWidget {
  final StoreModel store;

  /// Tipe pesanan yang sedang dipilih: 'delivery' atau 'pickup'.
  final String fulfillmentType;

  /// Dipanggil saat pembeli berpindah antara Pesan Antar dan Pickup.
  final ValueChanged<String> onFulfillmentChanged;

  const StoreHeader({
    super.key,
    required this.store,
    required this.fulfillmentType,
    required this.onFulfillmentChanged,
  });

  Widget _fulfillmentOption({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final bool isSelected = fulfillmentType == value;

    return Expanded(
      child: InkWell(
        onTap: () => onFulfillmentChanged(value),
        borderRadius: const BorderRadius.all(CustomerUi.controlRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.bgWhite : Colors.transparent,
            borderRadius: const BorderRadius.all(CustomerUi.controlRadius),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? AppColors.primaryPink : Colors.grey,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 12,
                  color: isSelected ? AppColors.primaryPink : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Titik toko belum pernah dipetakan kalau keduanya masih nol.
  bool get _hasLocation =>
      !(store.latitude == 0 && store.longitude == 0);

  /// Alamat dipakai kalau titiknya belum ada, supaya tombolnya tetap
  /// berguna untuk toko yang mengisi alamat tapi belum memetakan lokasi.
  String get _mapsQuery =>
      _hasLocation ? '${store.latitude},${store.longitude}' : store.address;

  Future<void> _openInMaps(BuildContext context) async {
    // Ditangkap dulu sebelum await supaya tidak memakai BuildContext
    // setelah operasi asynchronous.
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(_mapsQuery)}',
    );

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Tidak bisa membuka aplikasi peta.')),
      );
    }
  }

  Widget _locationCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
        decoration: CustomerUi.surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on,
                size: 16,
                color: AppColors.primaryPink,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  store.address.isEmpty
                      ? 'Alamat toko belum diisi.'
                      : store.address,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDark,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (_hasLocation) ...[
            const SizedBox(height: 10),
            // Pratinjau sengaja dibungkus IgnorePointer: kalau tidak,
            // gesekannya justru ditahan peta dan daftar menu di
            // bawahnya tidak bisa digulir.
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: IgnorePointer(
                child: SizedBox(
                  height: 130,
                  width: double.infinity,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter:
                          LatLng(store.latitude, store.longitude),
                      initialZoom: 16.5,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.nochy_eat',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point:
                                LatLng(store.latitude, store.longitude),
                            width: 44,
                            height: 44,
                            child: const Icon(
                              Icons.storefront,
                              color: AppColors.primaryPink,
                              size: 34,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (_mapsQuery.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: OutlinedButton.icon(
                onPressed: () => _openInMaps(context),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text(
                  'Buka di Google Maps',
                  style: TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryPink,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: BorderSide(
                    color: AppColors.primaryPink.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- BANNER TOKO ---
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 152,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(CustomerUi.cardRadius),
            border: Border.all(color: CustomerUi.border),
            image: DecorationImage(
              image: NetworkImage(
                store.imageUrl ??
                    'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?auto=format&fit=crop&w=800&q=80',
              ),
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // --- INFO TOKO & RATING ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: store.isOpen ? Colors.green : Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      store.isOpen ? 'BUKA' : 'TUTUP',
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (store.is24Hours) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPink,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '24 JAM',
                        style: TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      store.storeName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    store.rating.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDark),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      store.ratingCount > 0
                          ? '(${store.ratingCount} penilaian pembeli)'
                          : 'Belum ada penilaian',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // PILIHAN TIPE PESANAN
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: CustomerUi.blueTint,
                  borderRadius: const BorderRadius.all(CustomerUi.controlRadius),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _fulfillmentOption(
                          value: 'delivery',
                          label: 'Pesan Antar',
                          icon: Icons.delivery_dining_rounded,
                        ),
                        _fulfillmentOption(
                          value: 'pickup',
                          label: 'Ambil Sendiri',
                          icon: Icons.storefront_rounded,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                      child: Text(
                        fulfillmentType == 'pickup'
                            ? 'Kamu ambil sendiri di toko, tanpa ongkir dan tanpa driver.'
                            : 'Diantar driver ke alamatmu, ongkir Rp10.000.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // LOKASI TOKO — mengikuti titik yang dipilih seller lewat
              // form profil toko; titik yang sama juga dipakai sebagai
              // titik awal peta driver saat simulasi pengantaran.
              const SizedBox(height: 12),
              _locationCard(context),
            ],
          ),
        ),
      ],
    );
  }
}
