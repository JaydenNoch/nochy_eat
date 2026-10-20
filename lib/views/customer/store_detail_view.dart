import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nochy_eat/models/app_models.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/customer_ui.dart';
import 'package:nochy_eat/widgets/store_header.dart';
import 'package:nochy_eat/widgets/store_vouchers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Import CustomerHomeView dari folder universal
import 'package:nochy_eat/views/universal/customer_home_view.dart';

class StoreDetailView extends StatefulWidget {
  final StoreModel store;

  /// Isi keranjang awal — dipakai saat user menekan "Pesan Lagi"
  /// dari riwayat pesanan. Key = productId, value = quantity.
  final Map<String, int> initialCart;

  const StoreDetailView({
    super.key,
    required this.store,
    this.initialCart = const {},
  });

  @override
  State<StoreDetailView> createState() => _StoreDetailViewState();
}

class _StoreDetailViewState extends State<StoreDetailView>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<ProductModel> _products = [];
  bool _isLoading = true;
  late TabController _tabController;
  int _selectedCategoryIndex = 0;

  // State Keranjang Belanja: productId -> quantity
  final Map<String, int> _cartItems = {};

  // State Voucher
  Map<String, dynamic>? _appliedVoucher;
  List<Map<String, dynamic>> _userVouchers = [];
  List<Map<String, dynamic>> _storeVouchers = [];

  // Alamat pembeli untuk pengiriman (wajib sebelum checkout)
  String _deliveryAddress = '';

  // State Nochy Coins
  double _coinsBalance = 0.0;
  bool _useCoins = false; // toggle pakai coins saat checkout

  // Definisi efek voucher berdasarkan code
  static const Map<String, Map<String, dynamic>> _voucherRules = {
    'GRATISONGKIR10': {'type': 'free_delivery', 'maxDiscount': 10000.0, 'minOrder': 30000.0},
    'NOCHY50':        {'type': 'discount_percent', 'percent': 50, 'minOrder': 25000.0},
    'NEWUSER15':      {'type': 'discount_flat', 'amount': 15000.0, 'minOrder': 0.0},
    'CASHBACK30':     {'type': 'cashback_percent', 'percent': 30, 'minOrder': 50000.0},
  };

  // SERVER KEY MIDTRANS SANDBOX MILIKMU
  final String _midtransServerKey = 'SB-Mid-server-DA7YNP.Shl9lqHB3WqH-eMFd';

  /// Tipe pesanan yang sedang dipilih pembeli: 'delivery' atau 'pickup'.
  /// Disimpan di sini karena dipakai oleh semua jalur pembayaran.
  String _fulfillmentType = 'delivery';

  /// Ongkos kirim mengikuti tipe pesanan: ambil sendiri ya tidak ada ongkir.
  double get _deliveryFee => _fulfillmentType == 'pickup' ? 0.0 : 10000.0;

  /// Sidebar kategori di halaman toko. [key] harus cocok dengan kolom
  /// products.category; key kosong berarti menampilkan semua menu.
  static const List<({String key, String label})> _categories = [
    (key: '', label: 'Semua'),
    (key: 'flash_sale', label: 'Flash Sale'),
    (key: 'rekomendasi', label: 'Rekomendasi'),
    (key: 'makanan', label: 'MAKANAN'),
    (key: 'minuman', label: 'MINUMAN'),
    (key: 'snack', label: 'SNACK'),
  ];

  /// Menu yang boleh tampil sesuai kategori terpilih. [_products] sendiri
  /// tidak pernah diubah, karena isinya juga dipakai untuk keranjang.
  List<ProductModel> get _visibleProducts {
    final key = _categories[_selectedCategoryIndex].key;
    if (key.isEmpty) return _products;
    // Flash Sale diisi otomatis dari menu yang punya harga diskon, jadi
    // seller cukup mengisi "Harga diskon" di form menu. Satu menu boleh
    // terdaftar di banyak kategori, jadi sisanya dicek ke daftarnya.
    if (key == 'flash_sale') {
      return _products.where((p) => p.hasDiscount).toList();
    }
    return _products.where((p) => p.category?.contains(key) == true).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Pre-fill keranjang dari pesanan sebelumnya jika ada.
    if (widget.initialCart.isNotEmpty) {
      _cartItems.addAll(widget.initialCart);
    }
    _fetchStoreProducts();
  }

  Future<void> _fetchStoreProducts() async {
    try {
      final response = await _supabase
          .from('products')
          .select()
          .eq('store_id', widget.store.id);

      final List<dynamic> data = response;
      setState(() {
        _products = data.map((json) => ProductModel.fromJson(json)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
    _fetchStoreVouchers();
  }

  /// Ambil voucher yang dibuat seller untuk toko ini.
  ///
  /// Voucher yang sudah pernah dipakai user ini dibuang dari daftar:
  /// satu voucher toko hanya berlaku satu kali per user.
  Future<void> _fetchStoreVouchers() async {
    try {
      final data = await _supabase
          .from('store_vouchers')
          .select()
          .eq('store_id', widget.store.id)
          .eq('is_active', true);

      if (!mounted) return;
      List<Map<String, dynamic>> list =
          List<Map<String, dynamic>>.from(data);
      list = await _dropUsedStoreVouchers(list);
      setState(() => _storeVouchers = list);
    } catch (_) {}
  }

  /// Buang voucher toko yang sudah pernah dipakai oleh user ini.
  ///
  /// Kalau tabel catatannya belum dibuat (SQL belum dijalankan),
  /// daftar dikembalikan apa adanya supaya voucher tetap terpakai.
  Future<List<Map<String, dynamic>>> _dropUsedStoreVouchers(
      List<Map<String, dynamic>> vouchers) async {
    if (vouchers.isEmpty) return vouchers;
    final user = _supabase.auth.currentUser;
    if (user == null) return vouchers;

    try {
      final used = await _supabase
          .from('store_voucher_usages')
          .select('store_voucher_id')
          .eq('user_id', user.id);
      final usedIds =
          (used as List).map((e) => e['store_voucher_id'].toString()).toSet();
      return vouchers
          .where((v) => !usedIds.contains(v['id'].toString()))
          .toList();
    } catch (_) {
      return vouchers;
    }
  }

  /// Catat bahwa user ini sudah memakai voucher toko, supaya tidak
  /// bisa dipakai lagi oleh user yang sama. Dipanggil hanya setelah
  /// pembayaran benar-benar berhasil.
  Future<void> _recordStoreVoucherUsage(
      Map<String, dynamic> voucher, String? orderNumber) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      await _supabase.from('store_voucher_usages').insert({
        'user_id': user.id,
        'store_voucher_id': voucher['id'],
        'order_number': orderNumber,
      }).select().single();

      if (mounted) {
        setState(() {
          _storeVouchers
              .removeWhere((v) => v['id'] == voucher['id']);
          if (_appliedVoucher?['id'] == voucher['id']) {
            _appliedVoucher = null;
          }
        });
      }
    } catch (e) {
      // Gagal mencatat tidak boleh merusak checkout, tapi tetap
      // dicatat di log supaya terlihat saat debugging.
      debugPrint('Gagal catat pemakaian voucher toko: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _promptLogin(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primaryPink,
        duration: const Duration(seconds: 2),
      ),
    );

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => const CustomerHomeView(initialIndex: 2),
      ),
          (route) => false,
    );
  }

  int get _totalCartItems {
    return _cartItems.values.fold(0, (sum, quantity) => sum + quantity);
  }

  double get _totalCartPrice {
    double total = 0;
    _cartItems.forEach((productId, quantity) {
      final product = _products.firstWhere(
            (p) => p.id == productId,
        orElse: () => ProductModel(
          id: '',
          storeId: '',
          name: '',
          price: 0,
          isAvailable: true,
        ),
      );
      total += product.effectivePrice * quantity;
    });
    return total;
  }

  /// Tagihan sebelum koin: subtotal (sudah memakai harga diskon) ditambah
  /// ongkir lalu dikurangi potongan voucher yang sedang dipakai.
  double get _amountBeforeCoins =>
      _totalCartPrice + _deliveryFee - _calculateDiscount(_totalCartPrice);

  /// Nominal koin yang benar-benar dipakai, dibatasi supaya tidak melebihi
  /// tagihan dan tidak melebihi saldo.
  double get _coinsApplied => _useCoins
      ? (_coinsBalance >= _amountBeforeCoins
          ? _amountBeforeCoins
          : _coinsBalance)
      : 0.0;

  /// Total akhir yang ditampilkan dan ditagih. Dipakai bersama oleh bar
  /// bawah halaman toko dan rincian keranjang supaya angka yang dilihat
  /// customer selalu sama dengan angka yang dibayar.
  double get _finalCheckoutTotal {
    final total = _amountBeforeCoins - _coinsApplied;
    return total < 0 ? 0 : total;
  }

  void _addToCart(ProductModel product) {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      _promptLogin(
        'Silakan masuk/daftar terlebih dahulu untuk menambahkan menu',
      );
      return;
    }

    if (!product.isOrderable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Menu "${product.name}" sedang habis.'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    final currentQty = _cartItems[product.id] ?? 0;
    if (currentQty >= product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stok "${product.name}" tinggal ${product.stock}.'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    setState(() {
      _cartItems[product.id] = currentQty + 1;
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} ditambahkan ke keranjang! 🛒'),
        duration: const Duration(seconds: 1),
        backgroundColor: AppColors.primaryPink,
      ),
    );
  }

  void _removeFromCart(String productId) {
    setState(() {
      if (_cartItems.containsKey(productId)) {
        if (_cartItems[productId]! > 1) {
          _cartItems[productId] = _cartItems[productId]! - 1;
        } else {
          _cartItems.remove(productId);
        }
      }
    });
  }

  /// Hapus voucher dari Supabase setelah berhasil dipakai
  Future<void> _consumeVoucher(String voucherCode) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      await _supabase
          .from('user_vouchers')
          .delete()
          .eq('user_id', user.id)
          .eq('code', voucherCode);
      // Reset semua state voucher
      if (mounted) {
        setState(() {
          _appliedVoucher = null;
          _userVouchers.clear(); // kosongkan semua, akan di-fetch ulang saat buka cart lagi
        });
      }
    } catch (e) {
      debugPrint('Gagal hapus voucher: $e');
    }
  }

  /// Fetch voucher yang sudah diklaim user dari Supabase
  Future<void> _fetchUserVouchers() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final data = await _supabase
          .from('user_vouchers')
          .select()
          .eq('user_id', user.id);
      setState(() {
        _userVouchers = List<Map<String, dynamic>>.from(data);
      });
    } catch (_) {}
  }

  /// Fetch saldo Nochy Coins milik user
  Future<void> _fetchCoinsBalance() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      final data = await _supabase
          .from('profiles')
          .select('coins_balance')
          .eq('id', user.id)
          .maybeSingle();
      debugPrint('Coins fetched: ${data?['coins_balance']}');
      if (data != null && mounted) {
        setState(() {
          _coinsBalance = (data['coins_balance'] as num?)?.toDouble() ?? 0.0;
        });
      }
    } catch (e) {
      debugPrint('Fetch coins error: $e');
    }
  }

  /// Potong saldo coins setelah checkout dengan coins
  Future<bool> _deductCoins(double amount) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;
      final newBalance = _coinsBalance - amount;
      if (newBalance < 0) return false;
      await _supabase
          .from('profiles')
          .update({'coins_balance': newBalance})
          .eq('id', user.id);
      setState(() => _coinsBalance = newBalance);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Voucher yang sedang aktif adalah voucher toko buatan seller
  /// (bukan voucher aplikasi yang disimpan di `user_vouchers`).
  bool get _appliedVoucherIsStore =>
      _appliedVoucher != null && _appliedVoucher!.containsKey('discount_type');

  /// Hitung total diskon dari voucher yang dipakai.
  ///
  /// Mendukung dua sumber voucher:
  /// - voucher toko buatan seller (punya kolom `discount_type`), dan
  /// - voucher aplikasi (aturan hardcode di [_voucherRules]).
  double _calculateDiscount(double subtotal) {
    if (_appliedVoucher == null) return 0;

    // Voucher toko buatan seller.
    if (_appliedVoucher!.containsKey('discount_type')) {
      final voucher = StoreVoucherModel.fromJson(_appliedVoucher!);
      final discount = voucher.discountFor(subtotal);
      if (voucher.discountType == 'free_delivery') {
        // Gratis ongkir tidak boleh melebihi ongkir itu sendiri.
        // Pesanan ambil sendiri tidak dibebani ongkir sama sekali,
        // jadi diskonnya ikut nol dan voucher ini tidak berpengaruh.
        return discount > _deliveryFee ? _deliveryFee : discount;
      }
      return discount;
    }

    final code = _appliedVoucher!['code'] as String;
    final rule = _voucherRules[code];
    if (rule == null) return 0;

    final minOrder = (rule['minOrder'] as double);
    if (subtotal < minOrder) return 0;

    switch (rule['type']) {
      case 'free_delivery':
        // Dipatok pada ongkir yang benar-benar dibebankan, bukan angka
        // tetap — kalau tidak, ambil sendiri bisa dapat diskon ongkir
        // padahal ongkirnya nol sehingga totalnya jadi minus.
        return (rule['maxDiscount'] as double) > _deliveryFee
            ? _deliveryFee
            : (rule['maxDiscount'] as double);
      case 'discount_percent':
        return subtotal * (rule['percent'] as int) / 100;
      case 'discount_flat':
        return (rule['amount'] as double);
      case 'cashback_percent':
        return subtotal * (rule['percent'] as int) / 100;
      default:
        return 0;
    }
  }

  /// Cek apakah sebuah voucher (toko atau aplikasi) boleh dipakai untuk [subtotal].
  bool _isVoucherApplicable(Map<String, dynamic> voucher, double subtotal) {
    if (voucher.containsKey('discount_type')) {
      return subtotal >= StoreVoucherModel.fromJson(voucher).minOrder;
    }
    final rule = _voucherRules[voucher['code']];
    return rule != null && subtotal >= (rule['minOrder'] as double);
  }

  /// Pastikan pembeli sudah mengisi alamat & nomor HP sebelum checkout.
  ///
  /// Kalau belum lengkap, tampilkan ajakan untuk melengkapi profil.
  Future<bool> _ensureProfileComplete() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      _promptLogin('Silakan masuk/daftar terlebih dahulu untuk memesan.');
      return false;
    }

    try {
      final profile = await _supabase
          .from('profiles')
          .select('address, phone')
          .eq('id', user.id)
          .maybeSingle();

      final address = profile?['address']?.toString().trim() ?? '';
      final phone = profile?['phone']?.toString().trim() ?? '';

      if (address.isNotEmpty && phone.isNotEmpty) {
        _deliveryAddress = address;
        return true;
      }

      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Lengkapi Data Dulu 📍'),
          content: const Text(
            'Kamu perlu mengisi alamat pengiriman dan nomor HP sebelum '
            'melakukan checkout. Yuk lengkapi dulu di halaman profil.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Nanti'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CustomerHomeView(initialIndex: 2),
                  ),
                  (route) => false,
                );
              },
              child: const Text('Lengkapi Sekarang',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memeriksa profil: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    return false;
  }

  /// Request Snap Token Asli ke API Midtrans
  Future<String?> _getMidtransSnapUrl(double totalAmount, String orderId) async {
    const url = 'https://app.sandbox.midtrans.com/snap/v1/transactions';
    final authHeader = 'Basic ${base64Encode(utf8.encode('$_midtransServerKey:'))}';

    // Ambil email user — pastikan valid format RFC (harus ada domain.tld)
    final userEmail = _supabase.auth.currentUser?.email;
    final emailRegex = RegExp(r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
    final isValidEmail = userEmail != null && emailRegex.hasMatch(userEmail);
    final emailToSend = isValidEmail ? userEmail : 'customer@nochy.id';


    final firstName = _supabase.auth.currentUser
        ?.userMetadata?['full_name']
        ?.toString()
        .split(' ')
        .first ?? 'Customer';

    try {
      final requestBody = {
        "transaction_details": {
          "order_id": orderId,
          "gross_amount": totalAmount.toInt(),
        },
        "credit_card": {"secure": true},
        "customer_details": {
          "email": emailToSend,
          "first_name": firstName,
        },
        "callbacks": {
          "finish": "https://nochy-eat.app/payment/finish?status=success"
        }
      };

      debugPrint('Midtrans Request: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': authHeader,
        },
        body: jsonEncode(requestBody),
      );

      debugPrint('Midtrans Status: ${response.statusCode}');
      debugPrint('Midtrans Response: ${response.body}');

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final redirectUrl = data['redirect_url'] as String?;
        return redirectUrl;
      } else {
        if (mounted) {
          final errorBody = jsonDecode(response.body);
          final errorMsg = errorBody['error_messages']?.toString() ?? response.body;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Midtrans Error ${response.statusCode}: $errorMsg'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return null;
      }
    } catch (e) {
      debugPrint('Midtrans Exception: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Koneksi ke Midtrans gagal: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return null;
    }
  }

  /// Simpan pesanan beserta item-itemnya.
  ///
  /// Dipakai dua jalur pembayaran: Midtrans dan bayar penuh pakai
  /// Nochy Coins. Menyisipkan order_items jugalah yang memicu
  /// pemotongan stok di database, jadi pesanan tanpa item = stok
  /// tidak pernah berkurang.
  Future<String?> _createOrder({
    required String orderNumber,
    required double totalProductPrice,
    required double totalAmount,
    required String paymentMethod,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final isPickup = _fulfillmentType == 'pickup';

      final orderRes = await _supabase.from('orders').insert({
        'order_number': orderNumber,
        'customer_id': user.id,
        'store_id': widget.store.id,
        'total_product_price': totalProductPrice,
        'delivery_fee': _deliveryFee,
        'total_amount': totalAmount,
        'payment_method': paymentMethod,
        'payment_status': 'paid',
        'status': 'pending',
        // Pesanan ambil sendiri tidak dikirim ke mana-mana, jadi
        // alamatnya hanya penanda agar seller langsung paham bahwa
        // pesanan ini menunggu diambil pembelinya sendiri.
        'delivery_address': isPickup
            ? 'Ambil sendiri di toko'
            : (_deliveryAddress.isEmpty
                ? 'Alamat pengiriman belum diisi'
                : _deliveryAddress),
        'fulfillment_type': _fulfillmentType,
      }).select().single();

      debugPrint('✅ Order saved: ${orderRes['id']}');

      for (final entry in _cartItems.entries) {
        final product = _products.firstWhere((p) => p.id == entry.key,
            orElse: () => ProductModel(
                id: '',
                storeId: '',
                name: '',
                price: 0,
                isAvailable: false));
        if (product.id.isNotEmpty) {
          await _supabase.from('order_items').insert({
            'order_id': orderRes['id'],
            'product_id': entry.key,
            'quantity': entry.value,
            'price_at_purchase': product.effectivePrice,
          });
          debugPrint('✅ Order item saved: ${product.name}');
        }
      }

      return orderRes['id'] as String?;
    } catch (e) {
      debugPrint('❌ Save order error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal simpan pesanan: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ));
      }
      return null;
    }
  }

  /// Jumlah total harga produk di keranjang, dihitung ulang dari data
  /// produk supaya tetap benar walau keranjang sudah berubah.
  double _currentTotalProductPrice() {
    double totalProductPrice = 0;
    _cartItems.forEach((productId, qty) {
      final product = _products.firstWhere((p) => p.id == productId,
          orElse: () => ProductModel(
              id: '', storeId: '', name: '', price: 0, isAvailable: false));
      totalProductPrice += product.effectivePrice * qty;
    });
    return totalProductPrice;
  }

  /// Membuka Snap Midtrans Asli via WebView
  Future<void> _openMidtransPayment({required double totalAmount}) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primaryPink),
      ),
    );

    final orderId = 'NOCHY-${DateTime.now().millisecondsSinceEpoch}';

    final String? redirectUrl = await _getMidtransSnapUrl(totalAmount, orderId);

    if (mounted) Navigator.pop(context); // tutup loading dialog

    // Kalau URL null (API gagal), stop — error sudah ditampilkan di _getMidtransSnapUrl
    if (redirectUrl == null) return;

    // Simpan voucher yang dipakai sebelum WebView dibuat, supaya tidak
    // bergantung pada _appliedVoucher yang bisa berubah selama proses.
    final Map<String, dynamic>? voucherUsed = _appliedVoucher;

    // Flag agar handlePaymentSuccess hanya dipanggil sekali
    bool _paymentHandled = false;
    bool _isVerifyingPayment = false;

    Future<void> handlePaymentSuccess() async {
      if (_paymentHandled || _isVerifyingPayment) return;
      _isVerifyingPayment = true;

      // Cek status ke Midtrans API
      try {
        final authHeader = 'Basic ${base64Encode(utf8.encode('$_midtransServerKey:'))}';
        final res = await http.get(
          Uri.parse('https://api.sandbox.midtrans.com/v2/$orderId/status'),
          headers: {'Authorization': authHeader},
        );
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final status = data['transaction_status'] as String?;
          final isPaid = status == 'settlement' || status == 'capture';
          if (!isPaid) {
            _isVerifyingPayment = false;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Pembayaran belum terkonfirmasi (status: $status)'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ));
            }
            return;
          }
        }
      } catch (e) {
        debugPrint('Verify payment error: $e');
        // Kalau gagal cek (network error), tetap lanjut agar tidak block user
      }

      _paymentHandled = true;
      // Pembayaran sudah terkonfirmasi: voucher toko dicatat sebagai
      // terpakai (hangus untuk user ini), voucher aplikasi dihapus
      // dari daftar klaim user.
      if (voucherUsed != null) {
        if (voucherUsed.containsKey('discount_type')) {
          await _recordStoreVoucherUsage(voucherUsed, orderId);
        } else if (voucherUsed['code'] != null) {
          _consumeVoucher(voucherUsed['code'] as String);
        }
      }

      // Simpan order ke database. Penyisipan order_items di dalamnya
      // jugalah yang memotong stok produk.
      await _createOrder(
        orderNumber: orderId,
        totalProductPrice: _currentTotalProductPrice(),
        totalAmount: totalAmount,
        paymentMethod: 'midtrans',
      );

      if (mounted) Navigator.pop(context);
      setState(() {
        _cartItems.clear();
        _appliedVoucher = null;
        _useCoins = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pembayaran Midtrans Berhasil! Pesanan diproses 🛵'),
          backgroundColor: Colors.green,
        ),
      );
    }

    final controller = WebViewController();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(false)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('WebView loading: $url');
            final isSuccess = url.contains('transaction_status=settlement') ||
                url.contains('transaction_status=capture') ||
                url.contains('status_code=200') ||
                url.contains('#/success') ||
                url.contains('/finish') ||
                url.contains('nochy-eat.app/payment/finish');
            if (isSuccess) handlePaymentSuccess();
          },
          onPageFinished: (String url) {
            debugPrint('WebView finished: $url');
          },
          onUrlChange: (UrlChange change) {
            final url = change.url ?? '';
            debugPrint('WebView URL change: $url');
            final isSuccess = url.contains('transaction_status=settlement') ||
                url.contains('transaction_status=capture') ||
                url.contains('status_code=200') ||
                url.contains('#/success') ||
                url.contains('/finish') ||
                url.contains('nochy-eat.app/payment/finish');
            if (isSuccess) handlePaymentSuccess();
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView Error: ${error.description}');
          },
        ),
      )
      ..loadRequest(
        Uri.parse(redirectUrl),
        headers: {'Accept': 'text/html,application/xhtml+xml,application/xml'},
      );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Midtrans Payment 💳',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.textDark,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ClipRRect(
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
                  child: WebViewWidget(
                    controller: controller,
                    gestureRecognizers: {
                      Factory<VerticalDragGestureRecognizer>(
                            () => VerticalDragGestureRecognizer(),
                      ),
                      Factory<HorizontalDragGestureRecognizer>(
                            () => HorizontalDragGestureRecognizer(),
                      ),
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// BottomSheet Detail Keranjang Saya (Tambah/Kurang Item)
  void _showCartDetailsBottomSheet() async {
    // Fetch voucher dan coins dulu, baru buka bottomsheet
    await Future.wait([
      _fetchUserVouchers(),
      _fetchCoinsBalance(),
      _fetchStoreVouchers(),
    ]);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final cartProducts = _products
                .where((p) =>
            _cartItems.containsKey(p.id) && _cartItems[p.id]! > 0)
                .toList();

            final double subtotal = _totalCartPrice;
            final double deliveryFee = _deliveryFee;
            final double discount = _calculateDiscount(subtotal);
            // Koin dan total akhir ikut getter bersama supaya bar bawah
            // halaman toko menampilkan angka yang persis sama.
            final double coinsUsed = _coinsApplied;
            final double totalAfterDiscount = _finalCheckoutTotal;

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Keranjang Saya 🛒',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (cartProducts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Keranjang masih kosong',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.35,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: cartProducts.length,
                        separatorBuilder: (context, index) =>
                        const Divider(height: 24),
                        itemBuilder: (context, index) {
                          final product = cartProducts[index];
                          final qty = _cartItems[product.id] ?? 0;

                          return Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  product.imageUrl ??
                                      'https://images.unsplash.com/photo-1546069901-ba9599a7e63c',
                                  width: 54,
                                  height: 54,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        width: 54,
                                        height: 54,
                                        color: Colors.grey.shade200,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AppColors.textDark,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    if (product.hasDiscount)
                                      Text(
                                        'Rp ${product.price.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey.shade500,
                                          fontSize: 10,
                                          decoration:
                                              TextDecoration.lineThrough,
                                        ),
                                      ),
                                    Text(
                                      'Rp ${product.effectivePrice.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryPink,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () {
                                      _removeFromCart(product.id);
                                      setModalState(() {});
                                      setState(() {});
                                      if (_totalCartItems == 0) {
                                        Navigator.pop(context);
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                            color: AppColors.primaryPink),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(Icons.remove,
                                          size: 16,
                                          color: AppColors.primaryPink),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Text(
                                      '$qty',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      _addToCart(product);
                                      setModalState(() {});
                                      setState(() {});
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryPink,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(Icons.add,
                                          size: 16, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  const Divider(height: 1),

                  // --- SECTION VOUCHER ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: InkWell(
                      onTap: (_userVouchers.isEmpty && _storeVouchers.isEmpty)
                          ? null
                          : () {
                        // Tampilkan dialog pilih voucher
                        showDialog(
                          context: context,
                          builder: (dialogCtx) => AlertDialog(
                            title: const Text('Pilih Voucher 🎟️',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            content: SizedBox(
                              width: double.maxFinite,
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount:
                                    _userVouchers.length + _storeVouchers.length,
                                itemBuilder: (context, i) {
                                  final v = i < _userVouchers.length
                                      ? _userVouchers[i]
                                      : _storeVouchers[i - _userVouchers.length];
                                  final code = v['code'] as String;
                                  final isStoreVoucher = v.containsKey('discount_type');
                                  final isApplicable = _isVoucherApplicable(v, subtotal);
                                  final isSelected = _appliedVoucher?['code'] == code;

                                  return ListTile(
                                    leading: Icon(Icons.confirmation_number,
                                        color: isSelected
                                            ? AppColors.primaryPink
                                            : isApplicable
                                            ? Colors.green
                                            : Colors.grey),
                                    title: Text(v['title'] ?? code,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isApplicable ? AppColors.textDark : Colors.grey,
                                        )),
                                    subtitle: Text(
                                      isApplicable
                                          ? (isStoreVoucher
                                              ? StoreVoucherModel.fromJson(v).minOrderLabel
                                              : (v['min_order'] ?? ''))
                                          : 'Min. order tidak terpenuhi',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: isApplicable ? Colors.grey : Colors.red),
                                    ),
                                    trailing: isSelected
                                        ? const Icon(Icons.check_circle, color: AppColors.primaryPink)
                                        : null,
                                    onTap: isApplicable
                                        ? () {
                                      setState(() {
                                        _appliedVoucher = isSelected ? null : v;
                                      });
                                      Navigator.pop(dialogCtx);
                                      // setModalState setelah dialog tutup agar bottomsheet rebuild
                                      Future.microtask(() => setModalState(() {}));
                                    }
                                        : null,
                                  );
                                },
                              ),
                            ),
                            actions: [
                              if (_appliedVoucher != null)
                                TextButton(
                                  onPressed: () {
                                    setState(() => _appliedVoucher = null);
                                    Navigator.pop(dialogCtx);
                                    Future.microtask(() => setModalState(() {}));
                                  },
                                  child: const Text('Hapus Voucher', style: TextStyle(color: Colors.red)),
                                ),
                              TextButton(
                                onPressed: () => Navigator.pop(dialogCtx),
                                child: const Text('Tutup'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _appliedVoucher != null
                                ? Colors.green
                                : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          color: _appliedVoucher != null
                              ? Colors.green.shade50
                              : Colors.grey.shade50,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.confirmation_number,
                              color: _appliedVoucher != null ? Colors.green : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _appliedVoucher != null
                                    ? _appliedVoucher!['title'] ?? _appliedVoucher!['code']
                                    : (_userVouchers.isEmpty && _storeVouchers.isEmpty)
                                    ? 'Belum ada voucher tersedia'
                                    : 'Pilih Voucher (${_userVouchers.length + _storeVouchers.length} tersedia)',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _appliedVoucher != null ? Colors.green.shade700 : Colors.grey.shade600,
                                ),
                              ),
                            ),
                            Icon(
                              _appliedVoucher != null ? Icons.check_circle : Icons.chevron_right,
                              color: _appliedVoucher != null ? Colors.green : Colors.grey,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // --- SECTION NOCHY COINS ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: InkWell(
                      onTap: _coinsBalance <= 0 ? null : () {
                        setState(() => _useCoins = !_useCoins);
                        setModalState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _useCoins ? AppColors.highlightYellow : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          color: _useCoins ? Colors.amber.shade50 : Colors.grey.shade50,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.monetization_on,
                                color: _coinsBalance > 0 ? AppColors.highlightYellow : Colors.grey,
                                size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Nochy Coins — Rp ${_coinsBalance.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: _coinsBalance > 0 ? AppColors.textDark : Colors.grey,
                                    ),
                                  ),
                                  if (_coinsBalance <= 0)
                                    const Text('Saldo tidak cukup', style: TextStyle(fontSize: 11, color: Colors.grey))
                                  else if (_useCoins)
                                    Text(
                                      'Akan digunakan: Rp ${(_coinsBalance >= subtotal + _deliveryFee - (_calculateDiscount(subtotal)) ? subtotal + _deliveryFee - (_calculateDiscount(subtotal)) : _coinsBalance).toStringAsFixed(0)}',
                                      style: const TextStyle(fontSize: 11, color: Colors.amber),
                                    )
                                  else
                                    const Text('Ketuk untuk bayar dengan Coins', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            if (_coinsBalance > 0)
                              Switch(
                                value: _useCoins,
                                activeColor: AppColors.highlightYellow,
                                onChanged: (val) {
                                  setState(() => _useCoins = val);
                                  setModalState(() {});
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // --- RINGKASAN HARGA ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _buildPriceRow('Subtotal', 'Rp ${subtotal.toStringAsFixed(0)}'),
                        _buildPriceRow('Ongkir', 'Rp ${deliveryFee.toStringAsFixed(0)}'),
                        if (discount > 0)
                          _buildPriceRow('Diskon Voucher', '- Rp ${discount.toStringAsFixed(0)}', isDiscount: true),
                        if (coinsUsed > 0)
                          _buildPriceRow('Nochy Coins', '- Rp ${coinsUsed.toStringAsFixed(0)}', isDiscount: true),
                        const Divider(height: 16),
                        _buildPriceRow('Total', 'Rp ${totalAfterDiscount.toStringAsFixed(0)}', isBold: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // --- TOMBOL CHECKOUT ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPink,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: cartProducts.isEmpty
                            ? null
                            : () async {
                          final ok = await _ensureProfileComplete();
                          if (!ok) return;

                          // Simpan voucher code dulu, JANGAN hapus sekarang
                          // Voucher akan dihapus SETELAH payment berhasil di handlePaymentSuccess

                          // Angkanya diambil dari getter bersama supaya tidak
                          // mungkin berbeda dengan yang ditampilkan di bar
                          // bawah halaman toko.
                          final double _coinsUsed = _coinsApplied;
                          final double _finalTotal = _finalCheckoutTotal;

                          Navigator.pop(context);

                          if (_useCoins && _coinsUsed > 0) {
                            _deductCoins(_coinsUsed).then((success) async {
                              if (!success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Saldo Nochy Coins tidak cukup'), backgroundColor: Colors.red),
                                );
                                return;
                              }
                              setState(() => _useCoins = false);
                              if (_finalTotal <= 0) {
                                // Bayar penuh pakai Coins. Pesanan tetap harus
                                // dibuat: tanpa baris orders, order_items tidak
                                // pernah masuk sehingga stok tidak terpotong dan
                                // seller tidak melihat pesanan masuk sama sekali.
                                final String newOrderNumber =
                                    'NOCHY-${DateTime.now().millisecondsSinceEpoch}';

                                final createdOrderId = await _createOrder(
                                  orderNumber: newOrderNumber,
                                  totalProductPrice: _currentTotalProductPrice(),
                                  totalAmount: _coinsUsed,
                                  paymentMethod: 'coins',
                                );

                                // Coins sudah terpotong, jadi kalau pesanan gagal
                                // disimpan kita berhenti di sini dan keranjang
                                // dibiarkan utuh agar bisa dicoba ulang.
                                if (createdOrderId == null) return;

                                // Voucher hangus baru setelah pembayaran berhasil.
                                if (_appliedVoucher != null) {
                                  if (_appliedVoucherIsStore) {
                                    await _recordStoreVoucherUsage(
                                        _appliedVoucher!, newOrderNumber);
                                  } else if (_appliedVoucher!['code'] != null) {
                                    _consumeVoucher(
                                        _appliedVoucher!['code'] as String);
                                  }
                                }

                                if (!mounted) return;
                                setState(() {
                                  _cartItems.clear();
                                  _appliedVoucher = null;
                                  _useCoins = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Pesanan berhasil dibayar dengan Nochy Coins! 🛵'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } else {
                                _openMidtransPayment(totalAmount: _finalTotal);
                              }
                            });
                          } else {
                            _openMidtransPayment(totalAmount: _finalTotal);
                          }
                        },
                        child: Text(
                          'Checkout • Rp ${totalAfterDiscount.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPriceRow(String label, String value, {bool isBold = false, bool isDiscount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(
            fontSize: 13,
            color: isDiscount ? Colors.green : Colors.grey.shade600,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          )),
          Text(value, style: TextStyle(
            fontSize: 13,
            color: isDiscount ? Colors.green : (isBold ? AppColors.primaryPink : AppColors.textDark),
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalItems = _totalCartItems;
    final totalPrice = _totalCartPrice;
    final visibleProducts = _visibleProducts;

    return Scaffold(
      backgroundColor: AppColors.bgLightGrey,
      appBar: AppBar(
        backgroundColor: AppColors.bgWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => Navigator.pop(context),
        ),

      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: AppColors.primaryPink))
          : SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: StoreHeader(
                store: widget.store,
                fulfillmentType: _fulfillmentType,
                onFulfillmentChanged: (value) =>
                    setState(() => _fulfillmentType = value),
              ),
            ),
            SliverToBoxAdapter(
              child: StoreVouchers(storeId: widget.store.id),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyTabBarDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primaryPink,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppColors.primaryPink,
                  indicatorWeight: 3,
                  tabs: const [
                    Tab(text: 'Menu'),
                    Tab(text: 'Untukmu'),
                  ],
                ),
              ),
            ),
          ],
          body: Row(
            children: [
              Container(
                width: 100,
                color: CustomerUi.blueTint,
                child: ListView.builder(
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final isSelected =
                        index == _selectedCategoryIndex;
                    return InkWell(
                      onTap: () => setState(
                              () => _selectedCategoryIndex = index),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 8),
                          color: isSelected
                              ? Colors.white
                              : CustomerUi.blueTint,
                        child: Text(
                          _categories[index].label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? AppColors.primaryPink
                                : AppColors.textDark,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: visibleProducts.isEmpty
                    ? Center(
                    child: Text(
                        _products.isEmpty
                            ? 'Belum ada menu'
                            : 'Belum ada menu di kategori ini',
                        style: const TextStyle(color: Colors.grey)))
                    : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 112),
                  itemCount: visibleProducts.length,
                  itemBuilder: (context, index) {
                        final product = visibleProducts[index];
                        final qty = _cartItems[product.id] ?? 0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(10),
                          decoration: CustomerUi.surface(),
                          child: Row(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius:
                                BorderRadius.circular(8),
                                child: Image.network(
                                  product.imageUrl ??
                                      'https://images.unsplash.com/photo-1546069901-ba9599a7e63c',
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error,
                                      stackTrace) =>
                                      Container(
                                          width: 80,
                                          height: 80,
                                          color:
                                          Colors.grey.shade300),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AppColors.textDark,
                                      ),
                                      maxLines: 2,
                                      overflow:
                                      TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      product.description ??
                                          'Enak dan lezat',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey),
                                      maxLines: 1,
                                      overflow:
                                      TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                      MainAxisAlignment
                                          .spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            if (product.hasDiscount)
                                              Row(
                                                children: [
                                                  Text(
                                                    'Rp ${product.price.toStringAsFixed(0)}',
                                                    style: TextStyle(
                                                      fontWeight:
                                                      FontWeight.w500,
                                                      color:
                                                      Colors.grey.shade500,
                                                      fontSize: 10,
                                                      decoration:
                                                      TextDecoration
                                                          .lineThrough,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 4,
                                                        vertical: 1),
                                                    decoration:
                                                    BoxDecoration(
                                                      color: AppColors
                                                          .primaryPink,
                                                      borderRadius:
                                                      BorderRadius
                                                          .circular(4),
                                                    ),
                                                    child: Text(
                                                      '-${product.discountPercent}%',
                                                      style:
                                                      const TextStyle(
                                                        fontSize: 9,
                                                        fontWeight:
                                                        FontWeight.bold,
                                                        color:
                                                        Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            Text(
                                              'Rp ${product.effectivePrice.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                fontWeight:
                                                FontWeight.bold,
                                                color: AppColors
                                                    .primaryPink,
                                                fontSize: 14,
                                              ),
                                            ),
                                            Text(
                                              product.isOrderable
                                                  ? 'Sisa ${product.stock}'
                                                  : 'Habis',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight:
                                                FontWeight.bold,
                                                color: product.isOrderable
                                                    ? Colors.grey
                                                    : Colors.red,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (!product.isOrderable)
                                          Container(
                                            padding:
                                            const EdgeInsets
                                                .symmetric(
                                                horizontal: 8,
                                                vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.red
                                                  .withValues(
                                                  alpha: 0.1),
                                              borderRadius:
                                              BorderRadius
                                                  .circular(6),
                                            ),
                                            child: const Text(
                                              'Habis',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight:
                                                  FontWeight.bold,
                                                  color: Colors.red),
                                            ),
                                          )
                                        else if (qty == 0)
                                          InkWell(
                                            onTap: () =>
                                                _addToCart(product),
                                            child: Container(
                                              padding:
                                              const EdgeInsets
                                                  .all(6),
                                              decoration:
                                              BoxDecoration(
                                                color: AppColors
                                                    .primaryPink,
                                                borderRadius:
                                                BorderRadius
                                                    .circular(6),
                                              ),
                                              child: const Icon(
                                                  Icons.add,
                                                  color: Colors.white,
                                                  size: 16),
                                            ),
                                          )
                                        else
                                          Row(
                                            children: [
                                              InkWell(
                                                onTap: () =>
                                                    _removeFromCart(
                                                        product.id),
                                                child: Container(
                                                  padding:
                                                  const EdgeInsets
                                                      .all(4),
                                                  decoration:
                                                  BoxDecoration(
                                                    border: Border.all(
                                                        color: AppColors
                                                            .primaryPink),
                                                    borderRadius:
                                                    BorderRadius
                                                        .circular(
                                                        6),
                                                  ),
                                                  child: const Icon(
                                                      Icons.remove,
                                                      size: 14,
                                                      color: AppColors
                                                          .primaryPink),
                                                ),
                                              ),
                                              Padding(
                                                padding:
                                                const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 8),
                                                child: Text(
                                                  '$qty',
                                                  style:
                                                  const TextStyle(
                                                    fontWeight:
                                                    FontWeight
                                                        .bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              InkWell(
                                                onTap: () =>
                                                    _addToCart(
                                                        product),
                                                child: Container(
                                                  padding:
                                                  const EdgeInsets
                                                      .all(4),
                                                  decoration:
                                                  BoxDecoration(
                                                    color: AppColors
                                                        .primaryPink,
                                                    borderRadius:
                                                    BorderRadius
                                                        .circular(
                                                        6),
                                                  ),
                                                  child: const Icon(
                                                      Icons.add,
                                                      size: 14,
                                                      color:
                                                      Colors.white),
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
        ),
      ),
      bottomNavigationBar: totalItems == 0
          ? null
          : Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.primaryPink.withValues(alpha: 0.1),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: AppColors.primaryPink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    totalPrice < 30000
                        ? 'Tambah Rp ${(30000 - totalPrice).toStringAsFixed(0)} lagi untuk pakai voucher Gratis Ongkir Rp10RB!'
                        : 'Voucher Gratis Ongkir Rp10RB & Diskon 50% siap dipakai saat checkout!',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black.withValues(alpha: 0.8),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.keyboard_arrow_up,
                    size: 18, color: Colors.grey),
              ],
            ),
          ),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: _showCartDetailsBottomSheet,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryPink
                              .withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.shopping_basket_rounded,
                          color: AppColors.primaryPink,
                          size: 28,
                        ),
                      ),
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.primaryPink,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            '$totalItems',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: _showCartDetailsBottomSheet,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Rp ${_finalCheckoutTotal.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryPink,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.keyboard_arrow_up,
                              size: 16,
                              color: AppColors.primaryPink,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPink,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                    onPressed: () async {
                      final ok = await _ensureProfileComplete();
                      if (!ok) return;
                      // Satu-satunya jalur checkout: rincian keranjang. Di
                      // sana voucher, koin, dan ongkir ikut dihitung, jadi
                      // tombol ini tidak bisa lagi menagih angka yang beda.
                      _showCartDetailsBottomSheet();
                    },
                    child: const Text(
                      'Lanjut Checkout',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
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

/// Delegate untuk TabBar yang tetap nempel (sticky) saat scroll ke atas.
class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _StickyTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: AppColors.bgWhite,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar;
}
