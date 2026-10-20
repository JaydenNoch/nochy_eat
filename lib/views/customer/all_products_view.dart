import 'package:flutter/material.dart';
import 'package:nochy_eat/models/app_models.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/customer_ui.dart';
import 'package:nochy_eat/widgets/product_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AllProductsView extends StatefulWidget {
  const AllProductsView({super.key});

  @override
  State<AllProductsView> createState() => _AllProductsViewState();
}

class _AllProductsViewState extends State<AllProductsView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  List<ProductModel> _allProducts = [];
  List<ProductModel> _filteredProducts = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchAllProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllProducts() async {
    try {
      final response = await _supabase
          .from('products')
          .select('*, stores!inner(is_open)')
          .eq('is_available', true)
          .eq('stores.is_open', true);
      final List<dynamic> data = response;
      setState(() {
        _allProducts = data.map((json) => ProductModel.fromJson(json)).toList();
        _filteredProducts = _allProducts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _filterProducts(String query) {
    setState(() {
      _searchQuery = query.trim();
      if (_searchQuery.isEmpty) {
        _filteredProducts = _allProducts;
      } else {
        _filteredProducts = _allProducts
            .where((p) => p.name.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();
      }
    });
  }

  void _submitSearch() {
    _filterProducts(_searchController.text);
  }

  void _clearSearch() {
    _searchController.clear();
    _filterProducts('');
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
          'Semua Menu',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryPink))
          : SafeArea(
        child: Column(
          children: [
            Container(
              color: CustomerUi.pinkTint,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: TextField(
                        controller: _searchController,
                        onSubmitted: (value) => _submitSearch(),
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(fontSize: 14),
                        decoration: CustomerUi.searchDecoration(
                          hintText: 'Cari menu favoritmu di sini',
                          prefixIcon: IconButton(
                            icon: const Icon(Icons.search_rounded, color: AppColors.accentBlue),
                            onPressed: _submitSearch,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                                  onPressed: _clearSearch,
                               )
                               : null,
                        ),
                      ),
              ),
            const SizedBox(height: 12),

            // GRID KATALOG MAKANAN
            Expanded(
              child: _filteredProducts.isEmpty
                  ? Center(
                child: Text(
                  _searchQuery.isEmpty
                      ? 'Belum ada menu tersedia.'
                      : 'Menu "$_searchQuery" tidak ditemukan.',
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              )
                  : GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: MediaQuery.sizeOf(context).width >= 620 ? 3 : 2,
                  childAspectRatio: 0.72,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _filteredProducts.length,
                itemBuilder: (context, index) {
                  return ProductCard(product: _filteredProducts[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
