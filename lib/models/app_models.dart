class ProfileModel {
  final String id;
  final String fullName;
  final String? phone;
  final String role;
  final double coinsBalance;
  final String? avatarUrl;

  ProfileModel({
    required this.id,
    required this.fullName,
    this.phone,
    required this.role,
    required this.coinsBalance,
    this.avatarUrl,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'],
      fullName: json['full_name'] ?? '',
      phone: json['phone'],
      role: json['role'] ?? 'customer',
      coinsBalance: (json['coins_balance'] as num?)?.toDouble() ?? 0.0,
      avatarUrl: json['avatar_url'],
    );
  }
}

class StoreModel {
  final String id;
  final String merchantId;
  final String storeName;
  final String address;
  final double latitude;
  final double longitude;
  final bool isOpen;
  final double rating;
  final int ratingCount;
  final bool is24Hours;
  final String? imageUrl;

  StoreModel({
    required this.id,
    required this.merchantId,
    required this.storeName,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.isOpen,
    required this.rating,
    this.ratingCount = 0,
    this.is24Hours = false,
    this.imageUrl,
  });

  factory StoreModel.fromJson(Map<String, dynamic> json) {
    final rawImage = json['image_url'];
    return StoreModel(
      id: json['id'],
      merchantId: json['merchant_id'],
      storeName: json['store_name'] ?? '',
      address: json['address'] ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      isOpen: json['is_open'] ?? true,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
      is24Hours: json['is_24_hours'] == true,
      imageUrl: (rawImage is String && rawImage.trim().isNotEmpty)
          ? rawImage
          : null,
    );
  }
}

/// Voucher yang dibuat oleh seller untuk tokonya sendiri.
///
/// [discountType] salah satu dari 'percent', 'fixed', 'free_delivery'.
class StoreVoucherModel {
  final String id;
  final String storeId;
  final String code;
  final String title;
  final String? description;
  final String discountType;
  final double discountValue;
  final double? maxDiscount;
  final double minOrder;
  final bool isActive;

  StoreVoucherModel({
    required this.id,
    required this.storeId,
    required this.code,
    required this.title,
    this.description,
    required this.discountType,
    required this.discountValue,
    this.maxDiscount,
    required this.minOrder,
    required this.isActive,
  });

  factory StoreVoucherModel.fromJson(Map<String, dynamic> json) {
    return StoreVoucherModel(
      id: json['id']?.toString() ?? '',
      storeId: json['store_id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      discountType: json['discount_type']?.toString() ?? 'fixed',
      discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0.0,
      maxDiscount: (json['max_discount'] as num?)?.toDouble(),
      minOrder: (json['min_order'] as num?)?.toDouble() ?? 0.0,
      isActive: json['is_active'] != false,
    );
  }

  /// Hitung potongan untuk subtotal tertentu.
  double discountFor(double subtotal) {
    if (subtotal < minOrder) return 0;
    switch (discountType) {
      case 'percent':
        final raw = subtotal * discountValue / 100;
        if (maxDiscount != null && maxDiscount! > 0 && raw > maxDiscount!) {
          return maxDiscount!;
        }
        return raw;
      case 'free_delivery':
        return discountValue;
      case 'fixed':
      default:
        return discountValue;
    }
  }

  /// Teks singkat untuk chip, mis. "Diskon 20%" atau "Potongan Rp5.000".
  String get shortLabel {
    switch (discountType) {
      case 'percent':
        return 'Diskon ${discountValue.toStringAsFixed(0)}%';
      case 'free_delivery':
        return 'Gratis Ongkir';
      case 'fixed':
      default:
        return 'Potongan Rp${discountValue.toStringAsFixed(0)}';
    }
  }

  String get minOrderLabel => minOrder > 0
      ? 'Min. belanja Rp${minOrder.toStringAsFixed(0)}'
      : 'Tanpa minimum belanja';
}

class ProductModel {
  final String id;
  final String storeId;
  final String name;
  final String? description;
  final double price;
  final double? discountPrice;
  final String? imageUrl;
  final bool isAvailable;
  final int stock;

  /// Kategori tempat menu ini dipajang (flash_sale, rekomendasi,
  /// makanan, minuman, snack). Satu menu boleh masuk beberapa kategori
  /// sekaligus. Nullable karena kolomnya baru ditambah belakangan;
  /// menu yang belum dikategorikan hanya muncul di "Semua".
  final List<String>? category;

  ProductModel({
    required this.id,
    required this.storeId,
    required this.name,
    this.description,
    required this.price,
    this.discountPrice,
    this.imageUrl,
    required this.isAvailable,
    this.stock = 0,
    this.category,
  });

  /// Kolomnya berbentuk array, tapi tetap menampung string tunggal
  /// supaya aman selama database belum dimigrasi dan isinya masih teks.
  static List<String>? _parseCategory(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String && raw.isNotEmpty) return [raw];
    return null;
  }

  /// Produk dianggap masih bisa dipesan bila stoknya tersisa dan
  /// pemilik toko menandainya tersedia.
  bool get isOrderable => isAvailable && stock > 0;

  /// Harga yang benar-benar dibayar pembeli: harga diskon kalau ada dan
  /// memang lebih murah, selain itu harga normal. Data lama/typo (diskon
  /// nol, minus, atau lebih mahal dari harga normal) diabaikan supaya
  /// tidak ada transaksi yang tertagih lebih mahal dari seharusnya.
  double get effectivePrice {
    final diskon = discountPrice;
    if (diskon == null || diskon <= 0 || diskon >= price) return price;
    return diskon;
  }

  bool get hasDiscount => effectivePrice < price;

  /// Potongan dalam persen, dibulatkan ke bawah untuk badge "−20%".
  int get discountPercent =>
      hasDiscount ? ((price - effectivePrice) / price * 100).floor() : 0;

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'],
      storeId: json['store_id'],
      name: json['name'] ?? '',
      description: json['description'],
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      discountPrice: (json['discount_price'] as num?)?.toDouble(),
      imageUrl: json['image_url'],
      isAvailable: json['is_available'] ?? true,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      category: _parseCategory(json['category']),
    );
  }
}

class OrderModel {
  final String id;
  final String customerId;
  final String? driverId;
  final String storeId;
  final double totalAmount;
  final String status;
  final String paymentMethod;
  final DateTime createdAt;
  final String? storeName;
  final String? orderNumber;
  final String? deliveryAddress;
  final String? driverName;
  final String? driverPhone;
  final double? storeLatitude;
  final double? storeLongitude;

  /// 'delivery' diantar driver, 'pickup' diambil sendiri oleh
  /// customer. Nullable karena kolomnya baru ditambah belakangan.
  final String? fulfillmentType;

  OrderModel({
    required this.id,
    required this.customerId,
    this.driverId,
    required this.storeId,
    required this.totalAmount,
    required this.status,
    required this.paymentMethod,
    required this.createdAt,
    this.storeName,
    this.orderNumber,
    this.deliveryAddress,
    this.driverName,
    this.driverPhone,
    this.storeLatitude,
    this.storeLongitude,
    this.fulfillmentType,
  });

  /// Pesanan yang diambil sendiri di toko: tidak ada driver, tidak
  /// ada pelacakan, dan penilaian hanya untuk tokonya.
  bool get isPickup => fulfillmentType == 'pickup';

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    final store = json['stores'];
    final driver = json['driver'];
    return OrderModel(
      id: json['id'] ?? '',
      customerId: json['customer_id'] ?? '',
      driverId: json['driver_id'],
      storeId: json['store_id'] ?? '',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] ?? 'pending',
      paymentMethod: json['payment_method'] ?? 'cod',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      storeName: (store is Map) ? store['store_name']?.toString() : null,
      orderNumber: json['order_number']?.toString(),
      deliveryAddress: json['delivery_address']?.toString(),
      driverName: (driver is Map) ? driver['full_name']?.toString() : null,
      driverPhone: (driver is Map) ? driver['phone']?.toString() : null,
      storeLatitude: (store is Map)
          ? (store['latitude'] as num?)?.toDouble()
          : null,
      storeLongitude: (store is Map)
          ? (store['longitude'] as num?)?.toDouble()
          : null,
      fulfillmentType: json['fulfillment_type']?.toString(),
    );
  }
}