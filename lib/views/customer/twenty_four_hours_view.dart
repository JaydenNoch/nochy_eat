import 'package:flutter/material.dart';
import 'package:nochy_eat/models/app_models.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/customer_ui.dart';
import 'package:nochy_eat/views/customer/store_detail_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TwentyFourHoursView extends StatefulWidget {
  const TwentyFourHoursView({super.key});

  @override
  State<TwentyFourHoursView> createState() => _TwentyFourHoursViewState();
}

class _TwentyFourHoursViewState extends State<TwentyFourHoursView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<StoreModel> _stores = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch24HourStores();
  }

  Future<void> _fetch24HourStores() async {
    try {
      // Mengambil toko yang statusnya buka
      final response = await _supabase
          .from('stores')
          .select()
          .eq('is_open', true)
          .eq('is_24_hours', true);

      final List<dynamic> data = response;
      setState(() {
        _stores = data.map((json) => StoreModel.fromJson(json)).toList();
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
          'Kuliner Buka 24 Jam',
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
          onRefresh: _fetch24HourStores,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: CustomerUi.surface(color: CustomerUi.blueTint),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: AppColors.accentBlue,
                      borderRadius: BorderRadius.all(CustomerUi.controlRadius),
                    ),
                      child: const Icon(
                        Icons.access_time_filled_rounded,
                      color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Lapar Tengah Malam?',
                            style: TextStyle(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Daftar resto ini siap melayani pesananmu 24/7 non-stop!',
                            style: TextStyle(
                              color: AppColors.textDark.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Resto 24 Jam',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.shade200, width: 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Buka Sekarang',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // DAFTAR RESTO
              _stores.isEmpty
                  ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: Text(
                    'Tidak ada toko 24 jam yang tersedia.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
                  : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _stores.length,
                itemBuilder: (context, index) {
                  final store = _stores[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: CustomerUi.surface(),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          store.imageUrl ??
                              'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=300&q=80',
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 60,
                            height: 60,
                            color: Colors.grey.shade200,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              store.storeName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textDark,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryPink
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '24 JAM',
                              style: TextStyle(
                                fontSize: 9,
                                color: AppColors.primaryPink,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '• Buka Non-Stop',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDark
                                      .withValues(alpha: 0.5),
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
                                StoreDetailView(store: store),
                          ),
                        );
                      },
                    ),
                  );
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
