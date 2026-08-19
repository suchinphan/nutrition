/// Shared password policy used by both registration and password change.
///
/// Returns an error message if [value] doesn't satisfy the policy, or null
/// if it's valid. Previously register_page.dart and change_password_page.dart
/// enforced two different policies, so a password accepted at registration
/// could be rejected when changing it.
String? validatePassword(String value) {
  if (value.length < 8) {
    return 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร';
  }
  final policy = RegExp(r'(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[^A-Za-z0-9])');
  if (!policy.hasMatch(value)) {
    return 'รหัสผ่านต้องมีตัวพิมพ์ใหญ่ พิมพ์เล็ก ตัวเลข และอักขระพิเศษ';
  }
  return null;
}
