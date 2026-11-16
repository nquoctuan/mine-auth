import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../oauth_config.dart';

class DriveException implements Exception {
  DriveException(this.message, {this.needsSignIn = false});
  final String message;

  /// true khi phải đăng nhập lại (token bị thu hồi / hết hạn).
  final bool needsSignIn;
  @override
  String toString() => message;
}

/// Đồng bộ một file `vault.json` trong appDataFolder của Google Drive.
///
/// Đăng nhập bằng OAuth 2.0 + PKCE qua trình duyệt hệ thống, nhận kết quả ở
/// `http://127.0.0.1:<cổng ngẫu nhiên>` — dùng chung một luồng cho Windows và Android.
class GoogleDriveSync {
  GoogleDriveSync({this.refreshToken});

  static const _fileName = 'vault.json';

  String? refreshToken;
  String? _accessToken;
  DateTime _expiry = DateTime.fromMillisecondsSinceEpoch(0);
  String? _fileId;

  static String _randomUrlSafe(int bytes) {
    final rnd = Random.secure();
    return base64UrlEncode(List<int>.generate(bytes, (_) => rnd.nextInt(256)))
        .replaceAll('=', '');
  }

  /// Mở trình duyệt để đăng nhập Google. Sau khi xong, [refreshToken] có giá trị.
  Future<void> signIn() async {
    if (!OAuthConfig.isConfigured) {
      throw DriveException('Chưa cấu hình GOOGLE_CLIENT_ID (xem README)');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirectUri = 'http://127.0.0.1:${server.port}';
      final verifier = _randomUrlSafe(64);
      final challenge = base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');
      final state = _randomUrlSafe(16);

      final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': OAuthConfig.clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': OAuthConfig.scope,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
      });
      if (!await launchUrl(authUri, mode: LaunchMode.externalApplication)) {
        throw DriveException('Không mở được trình duyệt');
      }

      String? code;
      await for (final request in server.timeout(const Duration(minutes: 5))) {
        final q = request.uri.queryParameters;
        if (!q.containsKey('code') && !q.containsKey('error')) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          continue;
        }
        final ok = q['error'] == null && q['state'] == state && q['code'] != null;
        request.response.headers.contentType = ContentType.html;
        request.response.write('<!doctype html><meta charset="utf-8">'
            '<body style="font-family:sans-serif;text-align:center;padding-top:20vh">'
            '<h2>${ok ? 'Đã kết nối Google Drive' : 'Đăng nhập thất bại'}</h2>'
            '<p>Bạn có thể đóng tab này và quay lại Mine Auth.</p></body>');
        await request.response.close();
        if (!ok) {
          throw DriveException('Đăng nhập Google thất bại: ${q['error'] ?? 'state không khớp'}');
        }
        code = q['code'];
        break;
      }
      if (code == null) throw DriveException('Không nhận được mã đăng nhập');

      final json = await _tokenRequest({
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        'code_verifier': verifier,
      });
      final refresh = json['refresh_token'] as String?;
      if (refresh == null) {
        throw DriveException('Google không trả refresh token, hãy thử lại');
      }
      refreshToken = refresh;
      _storeAccessToken(json);
    } on TimeoutException {
      throw DriveException('Hết thời gian chờ đăng nhập');
    } finally {
      await server.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _tokenRequest(Map<String, String> params) async {
    final res = await http.post(
      Uri.https('oauth2.googleapis.com', '/token'),
      body: {
        'client_id': OAuthConfig.clientId,
        if (OAuthConfig.clientSecret.isNotEmpty)
          'client_secret': OAuthConfig.clientSecret,
        ...params,
      },
    );
    if (res.statusCode != 200) {
      final invalidGrant = res.body.contains('invalid_grant');
      throw DriveException(
        invalidGrant
            ? 'Phiên Google Drive đã hết hạn, hãy kết nối lại'
            : 'Lỗi lấy token (${res.statusCode}): ${res.body}',
        needsSignIn: invalidGrant,
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void _storeAccessToken(Map<String, dynamic> json) {
    _accessToken = json['access_token'] as String;
    final seconds = (json['expires_in'] as num?)?.toInt() ?? 3600;
    _expiry = DateTime.now().add(Duration(seconds: seconds - 60));
  }

  Future<Map<String, String>> _authHeaders() async {
    if (_accessToken == null || DateTime.now().isAfter(_expiry)) {
      final token = refreshToken;
      if (token == null) {
        throw DriveException('Chưa đăng nhập Google Drive', needsSignIn: true);
      }
      _storeAccessToken(await _tokenRequest({
        'grant_type': 'refresh_token',
        'refresh_token': token,
      }));
    }
    return {'Authorization': 'Bearer $_accessToken'};
  }

  Never _fail(String action, http.Response res) =>
      throw DriveException('Drive: $action thất bại (${res.statusCode})');

  Future<String?> _findFileId() async {
    if (_fileId != null) return _fileId;
    final res = await http.get(
      Uri.https('www.googleapis.com', '/drive/v3/files', {
        'spaces': 'appDataFolder',
        'q': "name = '$_fileName'",
        'orderBy': 'modifiedTime desc',
        'fields': 'files(id)',
      }),
      headers: await _authHeaders(),
    );
    if (res.statusCode != 200) _fail('tìm file', res);
    final files = (jsonDecode(res.body) as Map<String, dynamic>)['files'] as List;
    if (files.isEmpty) return null;
    return _fileId = (files.first as Map<String, dynamic>)['id'] as String;
  }

  /// Tải nội dung vault trên Drive; trả `null` nếu chưa có.
  Future<String?> download() async {
    final id = await _findFileId();
    if (id == null) return null;
    final res = await http.get(
      Uri.https('www.googleapis.com', '/drive/v3/files/$id', {'alt': 'media'}),
      headers: await _authHeaders(),
    );
    if (res.statusCode == 404) {
      _fileId = null;
      return null;
    }
    if (res.statusCode != 200) _fail('tải xuống', res);
    return utf8.decode(res.bodyBytes);
  }

  /// Ghi đè (hoặc tạo mới) vault trên Drive.
  Future<void> upload(String content) async {
    final headers = await _authHeaders();
    final id = await _findFileId();
    if (id != null) {
      final res = await http.patch(
        Uri.https('www.googleapis.com', '/upload/drive/v3/files/$id',
            {'uploadType': 'media'}),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: utf8.encode(content),
      );
      if (res.statusCode != 200) _fail('cập nhật', res);
      return;
    }

    const boundary = 'mine_auth_boundary_7f3a9c';
    final metadata = jsonEncode({
      'name': _fileName,
      'parents': ['appDataFolder'],
    });
    final body = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json\r\n\r\n'
        '$content\r\n'
        '--$boundary--';
    final res = await http.post(
      Uri.https('www.googleapis.com', '/upload/drive/v3/files',
          {'uploadType': 'multipart', 'fields': 'id'}),
      headers: {...headers, 'Content-Type': 'multipart/related; boundary=$boundary'},
      body: utf8.encode(body),
    );
    if (res.statusCode != 200) _fail('tạo file', res);
    _fileId = (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
  }
}
