import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Geocoding teks ke koordinat memakai Nominatim (OpenStreetMap).
///
/// Dipakai untuk menampilkan marker tujuan pelanggan di peta pelacakan.
/// Alamat pesanan disimpan sebagai teks bebas, jadi hasilnya bisa saja
/// tidak ketemu — pemanggil wajib menangani nilai null.
class GeocodingService {
  static const _headers = {'User-Agent': 'NochyEatApp/1.0'};

  static Future<LatLng?> forward(String address) async {
    final query = address.trim();
    if (query.isEmpty) return null;

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=json&limit=1&q=${Uri.encodeComponent(query)}',
      );
      final response = await http.get(url, headers: _headers).timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != 200) return null;

      final List data = json.decode(response.body);
      if (data.isEmpty) return null;

      return LatLng(
        double.parse(data[0]['lat'] as String),
        double.parse(data[0]['lon'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}
