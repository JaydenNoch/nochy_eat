import 'package:flutter/material.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/customer_ui.dart';
import 'package:nochy_eat/views/customer/nochy_deals_view.dart';

class NochyDealsBanner extends StatelessWidget {
  const NochyDealsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: CustomerUi.surface(color: AppColors.primaryPink, outlined: false),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const BoxDecoration(
                    color: AppColors.highlightYellow,
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                  child: const Text(
                    'MENU HEMAT',
                    style: TextStyle(
                      color: AppColors.textDark,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'NOCHY DEALS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Pilihan menu dengan harga hingga Rp25.000.',
                  style: TextStyle(color: Colors.white, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 42,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.highlightYellow,
                foregroundColor: AppColors.textDark,
                elevation: 0,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(CustomerUi.controlRadius),
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NochyDealsView(),
                  ),
                );
              },
              child: const Text('Lihat menu', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
