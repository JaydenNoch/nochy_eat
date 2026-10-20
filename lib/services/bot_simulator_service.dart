import 'dart:async';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

class BotSimulatorService {
  final SupabaseClient _supabase = Supabase.instance.client;
  Timer? _customerTimer;
  Timer? _merchantTimer;
  Timer? _driverTimer;

  // 1. Memulai Semua Bot Simulator
  void startAllBots() {
    print('🤖 Memulai Semua Bot Simulator NOCHY E-AT...');
    _startBotCustomer();
    _startBotMerchant();
    _startBotDriver();
  }

  // 2. Menghentikan Semua Bot
  void stopAllBots() {
    _customerTimer?.cancel();
    _merchantTimer?.cancel();
    _driverTimer?.cancel();
    print('🛑 Semua Bot Simulator dihentikan.');
  }

  // --- 🤖 BOT CUSTOMER: Otomatis Buat Pesanan ---
  void _startBotCustomer() {
    _customerTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        // Ambil toko yang buka
        final stores = await _supabase
            .from('stores')
            .select()
            .eq('is_open', true)
            .limit(1);

        if (stores.isEmpty) return;
        final store = stores[0];

        // Ambil customer acak dari profiles
        final customers = await _supabase
            .from('profiles')
            .select()
            .eq('role', 'customer')
            .limit(1);

        if (customers.isEmpty) return;
        final customer = customers[0];

        // Ambil produk dari toko tersebut
        final products = await _supabase
            .from('products')
            .select()
            .eq('store_id', store['id'])
            .eq('is_available', true);

        if (products.isEmpty) return;

        // Pilih 1 produk secara acak
        final product = products[Random().nextInt(products.length)];
        final double price = (product['discount_price'] ?? product['price']).toDouble();

        final orderNumber = 'DELIV-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

        // Masukkan ke tabel orders
        final orderRes = await _supabase.from('orders').insert({
          'order_number': orderNumber,
          'customer_id': customer['id'],
          'store_id': store['id'],
          'total_product_price': price,
          'delivery_fee': 10000.0,
          'total_amount': price + 10000.0,
          'payment_method': 'coins',
          'payment_status': 'paid',
          'status': 'pending',
          'delivery_address': 'Jl. Bot Customer No. ${Random().nextInt(100)}, Yogyakarta',
        }).select().single();

        // Masukkan ke order_items
        await _supabase.from('order_items').insert({
          'order_id': orderRes['id'],
          'product_id': product['id'],
          'quantity': 1,
          'price_at_purchase': price,
        });

        print('🤖 [BOT CUSTOMER] Berhasil membuat order baru: $orderNumber');
      } catch (e) {
        print('Error Bot Customer: $e');
      }
    });
  }

  // --- 🤖 BOT MERCHANT: Auto Accept & Cooking -> Ready ---
  void _startBotMerchant() {
    _merchantTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        // Cari pesanan yang masih pending
        final pendingOrders = await _supabase
            .from('orders')
            .select()
            .eq('status', 'pending')
            .limit(1);

        if (pendingOrders.isEmpty) return;
        final order = pendingOrders[0];
        final orderId = order['id'];

        // Ubah ke accepted
        await _supabase.from('orders').update({'status': 'accepted'}).eq('id', orderId);
        print('🤖 [BOT MERCHANT] Order ${order['order_number']} diterima (accepted).');

        // Jeda 5 detik lalu ubah ke cooking
        await Future.delayed(const Duration(seconds: 5));
        await _supabase.from('orders').update({'status': 'cooking'}).eq('id', orderId);
        print('🤖 [BOT MERCHANT] Order ${order['order_number']} sedang dimasak (cooking).');

        // Jeda 5 detik lagi lalu ubah ke ready_for_pickup
        await Future.delayed(const Duration(seconds: 5));
        await _supabase.from('orders').update({'status': 'ready_for_pickup'}).eq('id', orderId);
        print('🤖 [BOT MERCHANT] Order ${order['order_number']} siap diambil (ready_for_pickup).');
      } catch (e) {
        print('Error Bot Merchant: $e');
      }
    });
  }

  // --- 🤖 BOT DRIVER: Ambil Order, Live Tracking, & Selesai ---
  void _startBotDriver() {
    _driverTimer = Timer.periodic(const Duration(seconds: 12), (timer) async {
      try {
        // Cari driver di profiles
        final drivers = await _supabase
            .from('profiles')
            .select()
            .eq('role', 'driver')
            .limit(1);

        if (drivers.isEmpty) return;
        final driverId = drivers[0]['id'];

        // Cari order yang ready_for_pickup
        final readyOrders = await _supabase
            .from('orders')
            .select('*, stores(latitude, longitude)')
            .eq('status', 'ready_for_pickup')
            .filter('driver_id', 'is', null)
            .limit(1);

        if (readyOrders.isEmpty) return;
        final order = readyOrders[0];
        final orderId = order['id'];

        // Assign driver ke order dan ubah status jadi on_delivery
        await _supabase.from('orders').update({
          'driver_id': driverId,
          'status': 'on_delivery',
        }).eq('id', orderId);
        print('🤖 [BOT DRIVER] Driver mengambil order ${order['order_number']}.');

        // Simulasi pergerakan GPS (Waypoint dari Toko ke Customer)
        double startLat = order['stores']['latitude'];
        double startLng = order['stores']['longitude'];
        double targetLat = startLat + 0.005; // Titik dummy tujuan
        double targetLng = startLng + 0.005;

        // Loop simulasi jalan setiap 2 detik sebanyak 5 kali titik
        for (int i = 1; i <= 5; i++) {
          await Future.delayed(const Duration(seconds: 2));
          double currentLat = startLat + ((targetLat - startLat) * (i / 5));
          double currentLng = startLng + ((targetLng - startLng) * (i / 5));

          // Update posisi live tracking driver
          await _supabase.from('driver_locations').upsert({
            'driver_id': driverId,
            'order_id': orderId,
            'latitude': currentLat,
            'longitude': currentLng,
            'heading': 90.0 * i,
            'updated_at': DateTime.now().toIso8601String(),
          });
          print('🤖 [BOT DRIVER] Update posisi GPS live tracking...');
        }

        // Driver sampai di pelanggan, lalu pesanan dinyatakan selesai.
        await Future.delayed(const Duration(seconds: 2));
        await _supabase
            .from('orders')
            .update({'status': 'arrived'})
            .eq('id', orderId);
        await Future.delayed(const Duration(seconds: 2));
        await _supabase.from('orders').update({
          'status': 'completed',
          'delivery_photo_url': 'https://images.unsplash.com/photo-1584438784894-089d6a62b8fa',
        }).eq('id', orderId);
        print('🤖 [BOT DRIVER] Order ${order['order_number']} selesai (completed)!');
      } catch (e) {
        print('Error Bot Driver: $e');
      }
    });
  }
}