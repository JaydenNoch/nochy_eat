import 'package:flutter/material.dart';
import 'package:nochy_eat/models/app_models.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/customer_ui.dart';
import 'package:nochy_eat/widgets/product_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NochyDealsView extends StatefulWidget {
  const NochyDealsView({super.key});

  @override
  State<NochyDealsView> createState() => _NochyDealsViewState();
}

class _NochyDealsViewState extends State<NochyDealsView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<ProductModel> _dealProducts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDeals();
  }

  Future<void> _fetchDeals() async {
    try {
      // Ambil produk dengan harga di bawah/sama dengan 25.000 (Menu Murah)
      final response = await _supabase
          .from('products')
          .select()
          .lte('price', 25000)
          .eq('is_available', true);

      final List<dynamic> data = response;
      setState(() {
        _dealProducts = data.map((json) => ProductModel.fromJson(json)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
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
          'Nochy Deals',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppColors.textDark,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryPink))
          : SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryPink,
          onRefresh: _fetchDeals,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              // Full-width brand section (no card) — mirrors home header style
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 25, 16, 25),
                decoration: const BoxDecoration(
                  color: Color(0xFFFCE4EC),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.primaryPink.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.all(CustomerUi.controlRadius),
                        border: Border.all(color: AppColors.primaryPink.withValues(alpha: 0.2)),
                      ),
                      child: Icon(Icons.restaurant_rounded, color: AppColors.primaryPink, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Menu Pilihan',
                            style: TextStyle(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Daftar otomatis dari harga normal menu. Cocok buat makan hemat.',
                            style: TextStyle(
                              color: AppColors.textDark.withValues(alpha: 0.6),
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPink.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.all(CustomerUi.controlRadius),
                      ),
                      child: const Text(
                        'MURAH',
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // --- JUDUL DAFTAR MENU ---
              Padding(
                padding: CustomerUi.pagePadding,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Daftar Menu Nochy Deals',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      '${_dealProducts.length} Menu ditemukan',
                      style: const TextStyle(fontSize: 12, color: CustomerUi.mutedText),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // --- GRID PRODUK ---
              _dealProducts.isEmpty
                  ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Text(
                    'Belum ada menu promo murah tersedia.',
                    style: TextStyle(color: Colors.grey),
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
                itemCount: _dealProducts.length,
                itemBuilder: (context, index) {
                  return ProductCard(product: _dealProducts[index]);
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
