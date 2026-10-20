import 'package:flutter/material.dart';
import 'package:nochy_eat/models/app_models.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/customer_ui.dart';
import 'package:nochy_eat/views/customer/store_detail_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductCard extends StatelessWidget {
  final ProductModel product;

  const ProductCard({super.key, required this.product});

  /// Buka toko asal produk ini (bukan toko dummy).
  Future<void> _openStore(BuildContext context) async {
    try {
      final data = await Supabase.instance.client
          .from('stores')
          .select()
          .eq('id', product.storeId)
          .maybeSingle();

      if (!context.mounted) return;
      if (data == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Toko untuk menu ini sudah tidak tersedia.')),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StoreDetailView(store: StoreModel.fromJson(data)),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal membuka toko.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Buka toko untuk ${product.name}',
      child: Material(
        color: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(CustomerUi.cardRadius),
          side: const BorderSide(color: CustomerUi.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openStore(context),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                child: Image.network(
                  product.imageUrl ?? 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c',
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey.shade300),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (product.hasDiscount)
                    Row(
                      children: [
                        Text(
                          'Rp ${product.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: CustomerUi.mutedText,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primaryPink,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '-${product.discountPercent}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  Text(
                    'Rp ${product.effectivePrice.toStringAsFixed(0)}',
                    style: const TextStyle(color: AppColors.primaryPink, fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
