# Mine Auth

Authenticator cá nhân (TOTP, kiểu Google Authenticator) viết bằng Flutter, chạy trên **Windows** và **Android**, đồng bộ qua **Google Drive**.

- Mã TOTP theo RFC 6238 (SHA1/SHA256/SHA512, 6–8 chữ số, chu kỳ tuỳ chọn).
- Thêm tài khoản: quét QR bằng camera (Android), nhập secret key, hoặc dán link `otpauth://` (Windows và Android).
- Khoá bằng master password. Vault mã hoá AES-256-GCM, khoá sinh bằng Argon2id.
- Đồng bộ Google Drive: chỉ file đã mã hoá được đẩy lên, nằm trong thư mục dữ liệu ẩn của app (`appDataFolder`); app không có quyền đọc file khác trên Drive.

> **Trạng thái:** code được viết trong môi trường không cài được Flutter SDK nên **chưa được compile hay chạy thử**. Thuật toán TOTP và Base32 đã được đối chiếu với vector chuẩn bằng công cụ khác. Lần đầu hãy chạy `flutter analyze` và `flutter test` (bước 2) trước khi dùng thật.

## 1. Chuẩn bị

1. Cài [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) (bản stable, Dart ≥ 3.5).
2. Để build Windows: Visual Studio 2022 với workload "Desktop development with C++".
3. Để build Android: Android Studio (Android SDK). Chạy `flutter doctor` để kiểm tra.

## 2. Sinh thư mục nền tảng và chạy thử

Repo này chỉ chứa code Dart. Thư mục `windows/` và `android/` do Flutter sinh ra:

```powershell
cd C:\workspaces\jayeson\codebase\mine-auth
flutter create --platforms=windows,android --org com.jayeson --project-name mine_auth .
flutter pub get
flutter analyze
flutter test
```

Nếu `flutter create` sinh thêm `test/widget_test.dart` thì xoá file đó đi (nó tham chiếu app mẫu).

Sau đó mở `android/app/src/main/AndroidManifest.xml`, thêm 2 dòng ngay trong thẻ `<manifest>` (trước `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
```

Chạy:

```powershell
flutter run -d windows
flutter run -d <id-điện-thoại>     # xem id bằng: flutter devices
```

Chưa cần cấu hình Google Drive thì app vẫn chạy được, dữ liệu lưu trên máy.

## 3. Cấu hình Google Drive (làm một lần)

1. Vào <https://console.cloud.google.com/>, tạo project mới.
2. **APIs & Services → Library** → bật **Google Drive API**.
3. **OAuth consent screen**: loại *External*, thêm scope `.../auth/drive.appdata`, rồi thêm Gmail của bạn vào **Test users**.
   Khi app ở trạng thái *Testing*, Google thu hồi refresh token sau 7 ngày (phải kết nối lại). Bấm **Publish app** để hết giới hạn này; scope `drive.appdata` không thuộc nhóm phải thẩm định.
4. **Credentials → Create credentials → OAuth client ID** → loại **Desktop app**. Lấy *Client ID* và *Client secret*.
5. Truyền vào lúc chạy/build:

```powershell
flutter run -d windows --dart-define=GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com --dart-define=GOOGLE_CLIENT_SECRET=yyy
```

Trong app: bấm biểu tượng đám mây → **Kết nối Google Drive** → đăng nhập trong trình duyệt → quay lại app.

Cùng một OAuth client "Desktop app" được dùng cho cả Windows và Android: app mở trình duyệt hệ thống và nhận kết quả ở `http://127.0.0.1:<cổng ngẫu nhiên>` (OAuth 2.0 + PKCE). Với client loại Desktop, Google coi client secret là không bí mật, nhưng vẫn đừng đưa nó lên repo công khai.

## 4. Build bản phát hành

```powershell
flutter build windows --release --dart-define=GOOGLE_CLIENT_ID=... --dart-define=GOOGLE_CLIENT_SECRET=...
# kết quả: build\windows\x64\runner\Release\  (copy cả thư mục)

flutter build apk --release --dart-define=GOOGLE_CLIENT_ID=... --dart-define=GOOGLE_CLIENT_SECRET=...
# kết quả: build\app\outputs\flutter-apk\app-release.apk
```

## 5. Dùng trên máy thứ hai

1. Cài app, ở màn hình tạo vault nhập **đúng master password** đã dùng ở máy đầu.
2. Kết nối Google Drive cùng tài khoản. App tải vault về, gộp với dữ liệu trên máy rồi đẩy lên lại.

Quy tắc gộp: mỗi tài khoản OTP có thời điểm sửa cuối, bản mới hơn thắng; việc xoá cũng được đồng bộ. App đồng bộ khi mở khoá, sau mỗi lần thêm/sửa/xoá, và khi bấm **Đồng bộ ngay**.

## Cấu trúc code

| File | Nội dung |
| --- | --- |
| `lib/core/totp.dart`, `base32.dart` | Sinh mã TOTP, giải mã Base32 |
| `lib/core/otp_entry.dart` | Model tài khoản, đọc link `otpauth://`, gộp khi đồng bộ |
| `lib/core/vault_crypto.dart` | Argon2id + AES-256-GCM, định dạng file vault |
| `lib/core/vault_store.dart` | Đọc/ghi file trên máy |
| `lib/sync/google_drive.dart` | Đăng nhập OAuth, tải lên/xuống Drive |
| `lib/app_state.dart` | Trạng thái app: khoá/mở, CRUD, đồng bộ |
| `lib/ui/` | Màn hình khoá, danh sách mã, thêm/sửa, quét QR |
| `test/core_test.dart` | Test vector RFC 6238, otpauth, gộp, mã hoá vault |

Dữ liệu trên máy nằm ở thư mục application support của app (`vault.json` đã mã hoá, `drive_token.json` là refresh token Drive mã hoá bằng khoá vault).

## Giới hạn của bản này

- Chưa đổi được master password, chưa có mở khoá bằng vân tay / Windows Hello.
- Chưa import QR export của Google Authenticator (`otpauth-migration://`); cần quét lại QR gốc hoặc nhập secret.
- Trên Windows chưa đọc QR từ ảnh/màn hình, dùng nhập secret hoặc dán link `otpauth://`.
- Chỉ TOTP, không hỗ trợ HOTP.
- Quên master password là mất dữ liệu. Hãy giữ mã khôi phục (backup codes) của từng dịch vụ.
