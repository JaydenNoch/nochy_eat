import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:nochy_eat/models/app_models.dart';
import 'package:nochy_eat/theme/app_colors.dart';
import 'package:nochy_eat/theme/customer_ui.dart';
import 'package:nochy_eat/theme/customer_ui.dart';
import 'package:nochy_eat/views/customer/nearby_stores_view.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CustomerProfileView extends StatefulWidget {
  const CustomerProfileView({super.key});

  @override
  State<CustomerProfileView> createState() => _CustomerProfileViewState();
}

class _CustomerProfileViewState extends State<CustomerProfileView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  ProfileModel? _profile;
  String _savedAddress = 'Belum diatur';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final response = await _supabase
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (response != null) {
          setState(() {
            _profile = ProfileModel.fromJson(response);
            _savedAddress = response['address']?.toString() ?? 'Belum diatur';
            _isLoading = false;
          });
          return;
        }
      }

      setState(() {
        _profile = ProfileModel(
          id: 'cust-123',
          fullName: 'Ahmad',
          phone: '+62 812-3456-7890',
          role: 'customer',
          coinsBalance: 0.0,
          avatarUrl: null,
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  /// Dialog BottomSheet untuk Melakukan Top Up Nochy Coins

  static const String _midtransServerKey = 'SB-Mid-server-DA7YNP.Shl9lqHB3WqH-eMFd';

  /// Request Snap Token ke Midtrans untuk Top Up
  Future<String?> _getMidtransTopUpUrl(double amount, String orderId) async {
    const url = 'https://app.sandbox.midtrans.com/snap/v1/transactions';
    final authHeader = 'Basic ${base64Encode(utf8.encode('$_midtransServerKey:'))}';

    final userEmail = _supabase.auth.currentUser?.email;
    final emailRegex = RegExp(r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
    final emailToSend = (userEmail != null && emailRegex.hasMatch(userEmail))
        ? userEmail
        : 'customer@nochy.id';

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
            "gross_amount": amount.toInt(),
          },
          "credit_card": {"secure": true},
          "customer_details": {
            "email": emailToSend,
            "first_name": _profile?.fullName ?? 'Customer',
          },
          "callbacks": {
            "finish": "https://nochy-eat.app/topup/finish?status=success"
          }
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['redirect_url'] as String?;
      } else {
        if (mounted) {
          final err = jsonDecode(response.body);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Midtrans Error: ${err['error_messages']}'),
            backgroundColor: Colors.red,
          ));
        }
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Cek status transaksi ke Midtrans API
  Future<String?> _checkMidtransStatus(String orderId) async {
    try {
      final authHeader = 'Basic ${base64Encode(utf8.encode('$_midtransServerKey:'))}';
      final response = await http.get(
        Uri.parse('https://api.sandbox.midtrans.com/v2/$orderId/status'),
        headers: {'Authorization': authHeader},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['transaction_status'] as String?;
      }
    } catch (e) {
      debugPrint('Check status error: $e');
    }
    return null;
  }

  /// Buka WebView Midtrans untuk Top Up, lalu tambah coins setelah berhasil
  Future<void> _openMidtransTopUp(double nominal) async {
    final orderId = 'TOPUP-${DateTime.now().millisecondsSinceEpoch}';
    final String? redirectUrl = await _getMidtransTopUpUrl(nominal, orderId);
    if (redirectUrl == null) return;

    bool _handled = false;
    bool _isVerifying = false;

    Future<void> onTopUpSuccess() async {
      if (_handled || _isVerifying) return;
      _isVerifying = true;
      // Tampilkan loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Memverifikasi pembayaran...'),
            duration: Duration(seconds: 30),
          ),
        );
      }

      // Cek status ke Midtrans API
      final status = await _checkMidtransStatus(orderId);
      debugPrint('Midtrans status for $orderId: $status');

      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();

      final isPaid = status == 'settlement' ||
          status == 'capture' ||
          status == 'success';

      if (!isPaid) {
        _isVerifying = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                status == null
                    ? 'Gagal cek status pembayaran'
                    : 'Pembayaran belum terkonfirmasi (status: $status)',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Status confirmed → baru nambah coins
      _handled = true;
      try {
        final user = _supabase.auth.currentUser;
        if (user != null) {
          final data = await _supabase
              .from('profiles')
              .select('coins_balance')
              .eq('id', user.id)
              .maybeSingle();
          final currentBalance = (data?['coins_balance'] as num?)?.toDouble() ?? 0.0;
          final newBalance = currentBalance + nominal;
          await _supabase
              .from('profiles')
              .update({'coins_balance': newBalance})
              .eq('id', user.id);
          await _fetchProfile();
        }
      } catch (e) {
        debugPrint('Top up coins error: $e');
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Top Up Rp ${nominal.toStringAsFixed(0)} Berhasil! 🪙'),
          backgroundColor: Colors.green,
        ));
      }
    }

    final controller = WebViewController();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          final ok = url.contains('transaction_status=settlement') ||
              url.contains('transaction_status=capture') ||
              url.contains('nochy-eat.app/topup/finish') ||
              url.contains('#/success');
          if (ok) onTopUpSuccess();
        },
        onPageFinished: (url) {
          // Tidak inject JS — andalkan tombol konfirmasi manual
        },
        onUrlChange: (change) {
          final url = change.url ?? '';
          final ok = url.contains('transaction_status=settlement') ||
              url.contains('transaction_status=capture') ||
              url.contains('nochy-eat.app/topup/finish') ||
              url.contains('#/success');
          if (ok) onTopUpSuccess();
        },
      ))
      ..loadRequest(Uri.parse(redirectUrl));

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Top Up via Midtrans 🪙',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: WebViewWidget(
                  controller: controller,
                  gestureRecognizers: {
                    Factory<VerticalDragGestureRecognizer>(() => VerticalDragGestureRecognizer()),
                    Factory<HorizontalDragGestureRecognizer>(() => HorizontalDragGestureRecognizer()),
                  },
                ),
              ),
              // Tombol konfirmasi — hanya tampil kalau belum handled
              if (!_handled)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isVerifying ? null : () async {
                          setSheetState(() {});
                          await onTopUpSuccess();
                          setSheetState(() {});
                        },
                        icon: _isVerifying
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.check_circle, size: 18),
                        label: Text(
                          _isVerifying ? 'Memverifikasi...' : 'Konfirmasi Bayar Rp ${nominal.toStringAsFixed(0)} ✅',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTopUpBottomSheet() {
    final List<double> nominalOptions = [10000, 20000, 50000, 100000, 200000];
    double selectedNominal = 50000;
    String selectedPaymentType = 'E-Wallet (GoPay / QRIS)';
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Top Up Nochy Coins 🪙',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pilih Nominal Top Up',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: nominalOptions.map((amount) {
                      final isSelected = selectedNominal == amount;
                      return ChoiceChip(
                        label: Text(
                          'Rp ${amount.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textDark,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: AppColors.primaryPink,
                        backgroundColor: Colors.grey.shade100,
                        onSelected: (selected) {
                          if (selected) {
                            setModalState(() => selectedNominal = amount);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Metode Pembayaran (Midtrans)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  RadioListTile<String>(
                    title: const Text('E-Wallet (GoPay, QRIS, ShopeePay)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    value: 'E-Wallet (GoPay / QRIS)',
                    groupValue: selectedPaymentType,
                    activeColor: AppColors.primaryPink,
                    onChanged: (val) {
                      setModalState(() => selectedPaymentType = val!);
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('Transfer Bank VA (BCA, Mandiri, BNI)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    value: 'Transfer Bank (Virtual Account)',
                    groupValue: selectedPaymentType,
                    activeColor: AppColors.primaryPink,
                    onChanged: (val) {
                      setModalState(() => selectedPaymentType = val!);
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
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
                      onPressed: isProcessing
                          ? null
                          : () async {
                        setModalState(() => isProcessing = true);
                        Navigator.pop(context);
                        await _openMidtransTopUp(selectedNominal);
                        setModalState(() => isProcessing = false);
                      },
                      child: isProcessing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                        'Bayar Rp ${selectedNominal.toStringAsFixed(0)} via Midtrans',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
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

  Future<void> _saveAddressToDatabase(String newAddress) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        await _supabase
            .from('profiles')
            .update({'address': newAddress})
            .eq('id', user.id);

        setState(() {
          _savedAddress = newAddress;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Alamat pengiriman berhasil diperbarui! 📍'),
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

  void _showEditProfileBottomSheet() {
    final nameController =
    TextEditingController(text: _profile?.fullName ?? '');
    final phoneController = TextEditingController(
        text: _profile?.phone == 'Belum ada nomor HP'
            ? ''
            : (_profile?.phone ?? ''));
    final avatarController =
    TextEditingController(text: _profile?.avatarUrl ?? '');
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit Profil ✏️',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Nama Lengkap',
                        prefixIcon: const Icon(Icons.person,
                            color: AppColors.primaryPink),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Nomor Handphone',
                        hintText: 'Contoh: 081234567890',
                        prefixIcon: const Icon(Icons.phone,
                            color: AppColors.primaryPink),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: avatarController,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'URL Foto Profil (Avatar)',
                        hintText: 'https://example.com/foto.jpg',
                        prefixIcon: const Icon(Icons.image_outlined,
                            color: AppColors.primaryPink),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
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
                        onPressed: isSaving
                            ? null
                            : () async {
                          final newName = nameController.text.trim();
                          final newPhone = phoneController.text.trim();
                          final newAvatar = avatarController.text.trim();

                          if (newName.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Nama tidak boleh kosong'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          setModalState(() => isSaving = true);

                          try {
                            final user = _supabase.auth.currentUser;
                            if (user != null) {
                              await _supabase
                                  .from('profiles')
                                  .update({
                                'full_name': newName,
                                'phone': newPhone.isEmpty
                                    ? null
                                    : newPhone,
                                'avatar_url': newAvatar.isEmpty
                                    ? null
                                    : newAvatar,
                              })
                                  .eq('id', user.id);

                              await _fetchProfile();

                              if (mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Profil berhasil diperbarui! 🎉'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            setModalState(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Gagal memperbarui: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        child: isSaving
                            ? const CircularProgressIndicator(
                            color: Colors.white)
                            : const Text(
                          'Simpan Perubahan',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = _profile?.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.trim().isNotEmpty;
    final coinsBalance = _profile?.coinsBalance ?? 0.0;

    return Scaffold(
      backgroundColor: AppColors.bgLightGrey,
      appBar: AppBar(
        backgroundColor: CustomerUi.pinkTint,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: const Text(
          'Profil Saya',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: AppColors.primaryPink))
          : RefreshIndicator(
        color: AppColors.primaryPink,
        onRefresh: _fetchProfile,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // --- HEADER KARTU PROFIL ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: CustomerUi.surface(color: CustomerUi.pinkTint),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: hasAvatar ? () => _showPhotoZoom(context, avatarUrl) : null,
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: AppColors.primaryPink.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primaryPink.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child: hasAvatar
                            ? Image.network(
                          avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.person_rounded, size: 36, color: AppColors.primaryPink),
                        )
                            : const Icon(Icons.person_rounded, size: 36, color: AppColors.primaryPink),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _profile?.fullName ?? 'Pengguna Nochy',
                          style: const TextStyle(
                            color: AppColors.textDark,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (_profile?.phone == null ||
                              _profile!.phone!.trim().isEmpty)
                              ? 'Belum ada nomor HP'
                              : _profile!.phone!,
                          style: TextStyle(
                            color: AppColors.textDark.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primaryPink.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            (_profile?.role.toUpperCase() ?? 'CUSTOMER'),
                            style: const TextStyle(
                              color: AppColors.primaryPink,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.bgLightGrey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.edit_rounded,
                        color: AppColors.primaryPink, size: 20),
                    onPressed: _showEditProfileBottomSheet,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // --- KARTU NOCHY COINS ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CustomerUi.yellowTint,
                borderRadius: const BorderRadius.all(CustomerUi.cardRadius),
                border: Border.all(color: AppColors.highlightYellow),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.highlightYellow.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.monetization_on_rounded,
                            color: Colors.amber, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nochy Coins',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textDark.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Rp ${coinsBalance.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryPink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: _showTopUpBottomSheet,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text(
                        'Top Up',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // --- MENU AKUN & FITUR ---
            const Text(
              'Akun & Fitur',
              style: CustomerUi.sectionTitle,
            ),
            const SizedBox(height: 12),
            _buildMenuItem(
              icon: Icons.location_on_rounded,
              title: 'Alamat Pengiriman',
              subtitle: _savedAddress,
              onTap: () async {
                final selectedAddress = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => NearbyStoresView(
                      initialAddress: _savedAddress == 'Belum diatur'
                          ? 'Jl. Malioboro No. 10, Yogyakarta'
                          : _savedAddress,
                    ),
                  ),
                );

                if (selectedAddress != null && selectedAddress is String) {
                  _saveAddressToDatabase(selectedAddress);
                }
              },
            ),
            _buildMenuItem(
              icon: Icons.confirmation_number_rounded,
              title: 'Voucher Saya',
              subtitle: 'Lihat voucher yang kamu klaim & dari toko',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CustomerVouchersView(),
                  ),
                );
              },
            ),
            _buildMenuItem(
              icon: Icons.help_outline_rounded,
              title: 'Pusat Bantuan',
              subtitle: 'FAQ & CS Nochy E-AT',
              onTap: () {},
            ),
            const SizedBox(height: 20),

            // --- TOMBOL KELUAR ---
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade200, width: 1),
                  backgroundColor: AppColors.bgWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  await _supabase.auth.signOut();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Berhasil keluar')),
                    );
                  }
                },
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text(
                  'Keluar Akun',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: CustomerUi.surface(),
      child: Material(
        color: Colors.transparent,
        borderRadius: const BorderRadius.all(CustomerUi.controlRadius),
        child: InkWell(
          borderRadius: const BorderRadius.all(CustomerUi.controlRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPink.withValues(alpha: 0.1),
                    borderRadius: const BorderRadius.all(CustomerUi.controlRadius),
                  ),
                  child: Icon(icon, color: AppColors.primaryPink, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textDark.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPhotoZoom(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: ClipOval(
                    child: Image.network(
                      imageUrl,
                      width: 280,
                      height: 280,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 280,
                        height: 280,
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.person_rounded, size: 80, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 48,
                right: 16,
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerVouchersView extends StatefulWidget {
  const CustomerVouchersView({super.key});

  @override
  State<CustomerVouchersView> createState() => _CustomerVouchersViewState();
}

class _CustomerVouchersViewState extends State<CustomerVouchersView> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _myVouchers = [];
  List<Map<String, dynamic>> _storeVouchers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserVouchers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchUserVouchers();
  }

  Future<void> _fetchUserVouchers() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final data = await _supabase
            .from('user_vouchers')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false);

        final storeVoucherRows = await _supabase
            .from('store_vouchers')
            .select('*, stores(store_name)')
            .eq('is_active', true);

        final List<Map<String, dynamic>> storeVouchers =
        List<Map<String, dynamic>>.from(storeVoucherRows);

        try {
          final used = await _supabase
              .from('store_voucher_usages')
              .select('store_voucher_id')
              .eq('user_id', user.id);
          final usedIds = (used as List)
              .map((e) => e['store_voucher_id'].toString())
              .toSet();
          storeVouchers
              .removeWhere((v) => usedIds.contains(v['id'].toString()));
        } catch (_) {}

        setState(() {
          _myVouchers = List<Map<String, dynamic>>.from(data);
          _storeVouchers = storeVouchers;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CustomerUi.pinkTint,
      appBar: AppBar(
        backgroundColor: CustomerUi.pinkTint,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Voucher Saya',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w900,
            fontSize: 17,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(color: AppColors.primaryPink),
      )
          : RefreshIndicator(
        color: AppColors.primaryPink,
        onRefresh: _fetchUserVouchers,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          children: [
            const Text(
              'Voucher Diklaim',
              style: CustomerUi.sectionTitle,
            ),
            const SizedBox(height: 6),
            Text(
              'Gunakan voucher ini saat melakukan transaksi pemesanan.',
              style: CustomerUi.body,
            ),
            const SizedBox(height: 14),
            if (_myVouchers.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                decoration: CustomerUi.surface(),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPink.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.confirmation_number_outlined,
                        size: 38,
                        color: AppColors.primaryPink,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Belum Ada Voucher Diklaim',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Temukan berbagai penawaran diskon menarik dan klaim voucher pilihanmu sekarang.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textDark.withValues(alpha: 0.6),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._myVouchers.map(_buildClaimedVoucherCard),
            const SizedBox(height: 28),
            const Text(
              'Voucher Toko',
              style: CustomerUi.sectionTitle,
            ),
            const SizedBox(height: 6),
            Text(
              'Dibuat oleh resto. Pakai otomatis saat checkout di toko masing-masing.',
              style: CustomerUi.body,
            ),
            const SizedBox(height: 14),
            if (_storeVouchers.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                decoration: CustomerUi.surface(),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: const BorderRadius.all(CustomerUi.controlRadius),
                      ),
                      child: const Icon(Icons.store_rounded, color: Colors.grey, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tidak Ada Voucher Toko',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Belum ada voucher toko aktif yang tersedia saat ini.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textDark.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._storeVouchers.map(_buildStoreVoucherCard),
          ],
        ),
      ),
    );
  }

  Widget _buildClaimedVoucherCard(Map<String, dynamic> v) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: CustomerUi.surface(
        border: Border.all(color: AppColors.primaryPink.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryPink.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.all(CustomerUi.controlRadius),
            ),
            child: const Icon(
              Icons.confirmation_number_rounded,
              color: AppColors.primaryPink,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v['title'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  v['min_order'] ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primaryPink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  v['validity'] ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textDark.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreVoucherCard(Map<String, dynamic> v) {
    final store = v['stores'];
    final storeName = (store is Map) ? (store['store_name'] ?? '') : '';
    final type = v['discount_type']?.toString() ?? 'fixed';
    final value = (v['discount_value'] as num?)?.toDouble() ?? 0;
    final minOrder = (v['min_order'] as num?)?.toDouble() ?? 0;

    String headline;
    if (type == 'percent') {
      headline = 'Diskon ${value.toStringAsFixed(0)}%';
    } else if (type == 'free_delivery') {
      headline = 'Gratis Ongkir Rp${value.toStringAsFixed(0)}';
    } else {
      headline = 'Potongan Rp${value.toStringAsFixed(0)}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: CustomerUi.surface(
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.all(CustomerUi.controlRadius),
            ),
            child: const Icon(
              Icons.confirmation_number_rounded,
              color: Colors.green,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v['title'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  headline,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${storeName.isEmpty ? 'Toko' : storeName} • '
                      '${minOrder > 0 ? 'Min. Rp${minOrder.toStringAsFixed(0)}' : 'Tanpa minimum'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textDark.withValues(alpha: 0.4),
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
