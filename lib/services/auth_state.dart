/// Global flag agar router tidak pindah halaman saat proses register berjalan.
bool isHoldingRegisterState = false;

/// Data register yang berhasil, agar bisa ditampilkan di LoginView
/// meskipun widget-nya di-rebuild oleh RoleRouter.
class RegisterSuccessData {
  static bool success = false;
  static String email = '';
  static String role = '';

  static void set(String emailVal, String roleVal) {
    success = true;
    email = emailVal;
    role = roleVal;
  }

  static void clear() {
    success = false;
    email = '';
    role = '';
  }
}
