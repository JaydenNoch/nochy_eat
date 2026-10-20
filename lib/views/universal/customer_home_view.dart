import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nochy_eat/models/app_models.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/customer_ui.dart';
import 'package:nochy_eat/widgets/category_item.dart';
import 'package:nochy_eat/widgets/product_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nochy_eat/widgets/nochy_deals_banner.dart';

// Import dari folder customer
import 'package:nochy_eat/views/customer/all_products_view.dart';
import 'package:nochy_eat/views/customer/discount_deals_view.dart';
import 'package:nochy_eat/views/customer/my_orders_view.dart';
import 'package:nochy_eat/views/customer/nearby_stores_view.dart';
import 'package:nochy_eat/views/customer/twenty_four_hours_view.dart';
import 'package:nochy_eat/views/customer/vouchers_view.dart';

// Import dari folder universal
import 'package:nochy_eat/views/universal/profile_tab_wrapper.dart';
import 'package:nochy_eat/services/auth_state.dart';

class CustomerHomeView extends StatefulWidget {
  final int initialIndex;

  const CustomerHomeView({super.key, this.initialIndex = 0});

  @override
  State<CustomerHomeView> createState() => _CustomerHomeViewState();
}

class _CustomerHomeViewState extends State<CustomerHomeView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  List<ProductModel> _products = [];
  bool _isLoading = true;
  late int _currentIndex;
  String _searchQuery = '';

  // Variabel penampung alamat pengiriman aktif
  String _deliveryAddress = 'Pilih Lokasi Pengiriman >';

  // Counter untuk force rebuild ProfileTabWrapper saat tab Saya dipilih
  int _profileRefreshKey = 0;

  // Dinaikkan tiap kali tab "Pesanan Saya" dipilih atau user baru login.
  // MyOrdersView hidup di dalam IndexedStack sehingga initState-nya hanya
  // jalan sekali — tanpa pemicu ini daftar pesanan tidak pernah diambil ulang.
  int _ordersRefreshKey = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _fetchProducts();
    _fetchUserSavedAddress();

    if (RegisterSuccessData.success) {
      _currentIndex = 2;
    }

    // Listen perubahan auth (login/logout) untuk reload alamat
    _supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      final event = data.event;
      final user = data.session?.user;

      if ((event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession) &&
          user != null) {
        // Gunakan user dari event, bukan currentUser, untuk hindari race condition
        _fetchUserSavedAddressForUser(user.id);
      } else if (event == AuthChangeEvent.signedOut) {
        if (mounted) {
          setState(() {
            _deliveryAddress = 'Pilih Lokasi Pengiriman >';
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Mengambil alamat pengiriman tersimpan milik user dari Supabase
  Future<void> _fetchUserSavedAddress() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    await _fetchUserSavedAddressForUser(user.id);
  }

  /// Fetch alamat berdasarkan userId langsung (aman dari race condition auth)
  Future<void> _fetchUserSavedAddressForUser(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('address')
          .eq('id', userId)
          .maybeSingle();

      if (!mounted) return;

      if (response != null && response['address'] != null) {
        final savedAddress = response['address'].toString();
        if (savedAddress.trim().isNotEmpty) {
          setState(() {
            _deliveryAddress = savedAddress;
          });
        }
      }
    } catch (_) {}
  }

  /// Menyimpan alamat terpilih secara permanen ke database Supabase
  Future<void> _saveAddressToDatabase(String newAddress) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        await _supabase
            .from('profiles')
            .update({'address': newAddress})
            .eq('id', user.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Alamat pengiriman berhasil disimpan! 📍'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan alamat: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Menampilkan SnackBar peringatan seragam & mengarahkan ke Tab Saya (Login)
  void _promptLogin(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primaryPink,
        duration: const Duration(seconds: 2),
      ),
    );
    setState(() => _currentIndex = 2);
  }

  /// Memfilter daftar produk berdasarkan kata kunci pencarian
  List<ProductModel> get _filteredProducts {
    if (_searchQuery.trim().isEmpty) {
      return _products;
    }
    final query = _searchQuery.toLowerCase();
    return _products.where((p) {
      final nameMatches = p.name.toLowerCase().contains(query);
      final desc = p.description ?? '';
      final descMatches = desc.toLowerCase().contains(query);
      return nameMatches || descMatches;
    }).toList();
  }

  Future<void> _fetchProducts() async {
    try {
      // Hanya produk yang tersedia dari toko yang sedang buka.
      final response = await _supabase
          .from('products')
          .select('*, stores!inner(is_open)')
          .eq('is_available', true)
          .eq('stores.is_open', true);
      final List<dynamic> data = response;
      setState(() {
        _products = data.map((json) => ProductModel.fromJson(json)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLoggedIn = _supabase.auth.currentUser != null;

    // Home body & ProfileTabWrapper selalu dibuat ulang tiap build,
    // MyOrdersView memakai pemicu refresh supaya tidak fetch ulang tiap build.
    final List<Widget> pages = [
      _buildHomeBody(),
      MyOrdersView(refreshToken: _ordersRefreshKey),
      ProfileTabWrapper(
        key: ValueKey(_profileRefreshKey),
        onLoginSuccess: () {
          final user = _supabase.auth.currentUser;
          if (user != null) {
            _fetchUserSavedAddressForUser(user.id);
          }
          // Baru login → pesanan milik user ini belum pernah diambil.
          setState(() => _ordersRefreshKey++);
        },
      ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: CustomerUi.pinkTint,
        body: IndexedStack(
          index: _currentIndex,
          children: pages,
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: AppColors.bgWhite,
            border: const Border(top: BorderSide(color: CustomerUi.border)),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              if (index == 1 && !isLoggedIn) {
                _promptLogin(
                    'Silakan masuk/daftar terlebih dahulu untuk melihat pesanan.');
                return;
              }
              setState(() {
                if (index == 1) _ordersRefreshKey++;
                if (index == 2) _profileRefreshKey++;
                _currentIndex = index;
              });
            },
            selectedItemColor: AppColors.primaryPink,
            unselectedItemColor: AppColors.textDark.withValues(alpha: 0.5),
            backgroundColor: Colors.transparent,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: 12,
            ),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.restaurant_menu_rounded),
                label: 'Beranda',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.receipt_long_rounded),
                label: 'Pesanan Saya',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_rounded),
                label: 'Saya',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeBody() {
    final displayedProducts = _filteredProducts;

    return _isLoading
        ? const Center(
      child: CircularProgressIndicator(color: AppColors.primaryPink),
    )
        : SafeArea(
      child: RefreshIndicator(
        color: AppColors.primaryPink,
        onRefresh: () async {
          await _fetchProducts();
          await _fetchUserSavedAddress();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // The pink surface anchors the browse screen. Search stays white
            // so text and focus contrast remain clear.
            Container(
              decoration: const BoxDecoration(
                color: CustomerUi.pinkTint,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LOCATION ROW
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: CustomerUi.blueTint,
                          borderRadius: const BorderRadius.all(CustomerUi.controlRadius),
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: AppColors.accentBlue,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alamat Pengiriman',
                            style: TextStyle(
                              color: CustomerUi.mutedText,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      final bool isLoggedIn =
                          _supabase.auth.currentUser != null;

                      if (!isLoggedIn) {
                        _promptLogin(
                            'Silakan masuk/daftar terlebih dahulu untuk memilih lokasi.');
                        return;
                      }

                      final selectedAddress = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NearbyStoresView(
                            initialAddress:
                            _deliveryAddress == 'Pilih Lokasi Pengiriman >'
                                ? 'Jl. Malioboro No. 10, Yogyakarta'
                                : _deliveryAddress,
                          ),
                        ),
                      );

                      if (selectedAddress != null &&
                          selectedAddress is String) {
                        setState(() {
                          _deliveryAddress = selectedAddress;
                        });
                        _saveAddressToDatabase(selectedAddress);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _deliveryAddress,
                              style: const TextStyle(
                                color: AppColors.textDark,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.keyboard_arrow_right_rounded,
                            color: AppColors.accentBlue,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // SEARCHBAR
                  TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w500,
                      ),
                      onSubmitted: (value) {
                        setState(() {
                          _searchQuery = value.trim();
                        });
                      },
                      decoration: CustomerUi.searchDecoration(
                        hintText: 'Cari makanan, minuman, atau resto',
                        prefixIcon: IconButton(
                          icon: const Icon(
                            Icons.search_rounded,
                            color: AppColors.accentBlue,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _searchQuery =
                                  _searchController.text.trim();
                            });
                          },
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                          icon: const Icon(
                            Icons.clear_rounded,
                            color: Colors.grey,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                            : null,
                      ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Konten bawah header pakai background abu-abu supaya tidak pink semua
            Container(
              color: AppColors.bgLightGrey,
              child: Column(
                children: [
            // Actions are intentionally flat against the page: they are
            // navigation shortcuts, not another competing content card.
            Padding(
              padding: CustomerUi.pagePadding,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                    CategoryItem(
                      icon: Icons.local_fire_department,
                      label: 'Diskon Terus',
                      color: AppColors.highlightYellow,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DiscountDealsView(),
                          ),
                        );
                      },
                    ),
                    CategoryItem(
                      icon: Icons.near_me,
                      label: 'Sekitarmu',
                      color: AppColors.accentBlue,
                      onTap: () async {
                        final bool isLoggedIn =
                            _supabase.auth.currentUser != null;

                        if (!isLoggedIn) {
                          _promptLogin(
                              'Silakan masuk/daftar terlebih dahulu untuk memilih lokasi.');
                          return;
                        }

                        final selectedAddress = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => NearbyStoresView(
                              initialAddress: _deliveryAddress,
                            ),
                          ),
                        );

                        if (selectedAddress != null &&
                            selectedAddress is String) {
                          setState(() {
                            _deliveryAddress = selectedAddress;
                          });
                          _saveAddressToDatabase(selectedAddress);
                        }
                      },
                    ),
                    CategoryItem(
                      icon: Icons.access_time_filled,
                      label: 'Buka 24 Jam',
                      color: AppColors.primaryPink,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                            const TwentyFourHoursView(),
                          ),
                        );
                      },
                    ),
                    CategoryItem(
                      icon: Icons.card_giftcard,
                      label: 'Voucher',
                      color: AppColors.highlightYellow,
                      onTap: () {
                        final bool isLoggedIn =
                            _supabase.auth.currentUser != null;

                        if (!isLoggedIn) {
                          _promptLogin(
                              'Silakan masuk/daftar terlebih dahulu untuk melihat voucher.');
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const VouchersView(),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // --- BANNER NOCHY DEALS ---
            const Padding(
              padding: CustomerUi.pagePadding,
              child: NochyDealsBanner(),
            ),
            const SizedBox(height: 20),

            // --- JUDUL MENU PILIHAN ---
            Padding(
              padding: CustomerUi.pagePadding,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _searchQuery.isEmpty
                        ? 'Menu Pilihan Hari Ini'
                        : 'Hasil Pencarian "${_searchQuery.trim()}"',
                    style: CustomerUi.sectionTitle,
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AllProductsView(),
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: Text(
                        'Lihat Semua',
                        style: TextStyle(
                          color: AppColors.primaryPink,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // --- GRID PRODUK ---
            displayedProducts.isEmpty
                ? Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Text(
                  _searchQuery.isEmpty
                      ? 'Belum ada menu tersedia. Pastikan bot/data sudah terisi.'
                      : 'Menu "$_searchQuery" tidak ditemukan.',
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            )
                : GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: CustomerUi.pagePadding,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.sizeOf(context).width >= 620 ? 3 : 2,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: displayedProducts.length,
              itemBuilder: (context, index) =>
                  ProductCard(product: displayedProducts[index]),
            ),
            const SizedBox(height: 24),
                ],
              ),
            ), // end Container bgLightGrey
          ],
        ),
      ),
    );
  }
}
