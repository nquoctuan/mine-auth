/// Cấu hình OAuth cho đồng bộ Google Drive.
///
/// Tạo OAuth client loại "Desktop app" trên Google Cloud Console (xem README)
/// rồi điền vào đây, hoặc truyền lúc build:
///   flutter run --dart-define=GOOGLE_CLIENT_ID=... --dart-define=GOOGLE_CLIENT_SECRET=...
class OAuthConfig {
  static const clientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const clientSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET');

  /// Chỉ xin quyền thư mục dữ liệu riêng của app, không đọc được file khác trên Drive.
  static const scope = 'https://www.googleapis.com/auth/drive.appdata';

  static bool get isConfigured => clientId.isNotEmpty;
}
