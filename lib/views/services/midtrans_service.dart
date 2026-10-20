import 'dart:convert';
import 'package:http/http.dart' as http;

class MidtransService {
  // Server Key Sandbox Midtrans kamu
  static const String serverKey = 'SB-Mid-server-DA7YNP.Shl9lqHB3WqH-eMFd';

  static Future<String?> getSnapToken({
    required String orderId,
    required double grossAmount,
    required String customerName,
  }) async {
    const url = 'https://app.sandbox.midtrans.com/snap/v1/transactions';
    final authHeader = 'Basic ${base64Encode(utf8.encode('$serverKey:'))}';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': authHeader,
        },
        body: jsonEncode({
          "transaction_details": {
            "order_id": orderId,
            "gross_amount": grossAmount.toInt(),
          },
          "credit_card": {"secure": true},
          "customer_details": {
            "first_name": customerName,
          }
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['redirect_url']; // URL Snap Midtrans Asli
      } else {
        print('Midtrans Error: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Midtrans Exception: $e');
      return null;
    }
  }
}