import 'dart:math';

import 'base32.dart';
import 'totp.dart';

/// Một tài khoản OTP. Bản ghi đã xoá được giữ lại dạng "tombstone"
/// ([deleted] = true, secret rỗng) để việc xoá đồng bộ được sang máy khác.
class OtpEntry {
  const OtpEntry({
    required this.id,
    required this.issuer,
    required this.account,
    required this.secret,
    required this.updatedAt,
    this.algorithm = OtpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.deleted = false,
  });

  final String id;
  final String issuer;
  final String account;

  /// Secret dạng Base32 đã chuẩn hoá.
  final String secret;
  final OtpAlgorithm algorithm;
  final int digits;
  final int period;

  /// Thời điểm sửa cuối (ms từ epoch), dùng để gộp khi đồng bộ.
  final int updatedAt;
  final bool deleted;

  String get title => issuer.isNotEmpty ? issuer : account;

  String codeAt(DateTime time) => generateTotp(
        secret: base32Decode(secret),
        time: time,
        period: period,
        digits: digits,
        algorithm: algorithm,
      );

  static String newId() {
    final rnd = Random.secure();
    return List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static int now() => DateTime.now().millisecondsSinceEpoch;

  OtpEntry copyWith({
    String? issuer,
    String? account,
    String? secret,
    OtpAlgorithm? algorithm,
    int? digits,
    int? period,
    int? updatedAt,
    bool? deleted,
  }) =>
      OtpEntry(
        id: id,
        issuer: issuer ?? this.issuer,
        account: account ?? this.account,
        secret: secret ?? this.secret,
        algorithm: algorithm ?? this.algorithm,
        digits: digits ?? this.digits,
        period: period ?? this.period,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'issuer': issuer,
        'account': account,
        'secret': secret,
        'algorithm': algorithm.name,
        'digits': digits,
        'period': period,
        'updatedAt': updatedAt,
        'deleted': deleted,
      };

  factory OtpEntry.fromJson(Map<String, dynamic> json) => OtpEntry(
        id: json['id'] as String,
        issuer: (json['issuer'] as String?) ?? '',
        account: (json['account'] as String?) ?? '',
        secret: (json['secret'] as String?) ?? '',
        algorithm: OtpAlgorithm.values.firstWhere(
          (a) => a.name == json['algorithm'],
          orElse: () => OtpAlgorithm.sha1,
        ),
        digits: (json['digits'] as int?) ?? 6,
        period: (json['period'] as int?) ?? 30,
        updatedAt: (json['updatedAt'] as int?) ?? 0,
        deleted: (json['deleted'] as bool?) ?? false,
      );

  /// Đọc link `otpauth://totp/Issuer:account?secret=...` (nội dung mã QR).
  factory OtpEntry.fromUri(String raw) {
    final text = raw.trim();
    if (text.startsWith('otpauth-migration://')) {
      throw const FormatException(
          'Đây là mã QR export của Google Authenticator, bản này chưa hỗ trợ. Hãy quét QR gốc của từng dịch vụ.');
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'otpauth') {
      throw const FormatException('Không phải link otpauth://');
    }
    if (uri.host.toLowerCase() != 'totp') {
      throw const FormatException('Chỉ hỗ trợ TOTP (mã theo thời gian)');
    }

    final label = uri.pathSegments.join('/').trim();
    var issuer = '';
    var account = label;
    final colon = label.indexOf(':');
    if (colon >= 0) {
      issuer = label.substring(0, colon).trim();
      account = label.substring(colon + 1).trim();
    }
    final q = uri.queryParameters;
    final issuerParam = (q['issuer'] ?? '').trim();
    if (issuerParam.isNotEmpty) issuer = issuerParam;

    final secret = normalizeBase32(q['secret'] ?? '');
    base32Decode(secret); // kiểm tra hợp lệ

    final algorithm = switch ((q['algorithm'] ?? 'SHA1').toUpperCase()) {
      'SHA256' => OtpAlgorithm.sha256,
      'SHA512' => OtpAlgorithm.sha512,
      _ => OtpAlgorithm.sha1,
    };
    final digits = int.tryParse(q['digits'] ?? '') ?? 6;
    final period = int.tryParse(q['period'] ?? '') ?? 30;
    if (digits < 6 || digits > 8 || period <= 0) {
      throw const FormatException('Tham số digits/period không hợp lệ');
    }

    return OtpEntry(
      id: newId(),
      issuer: issuer,
      account: account,
      secret: secret,
      algorithm: algorithm,
      digits: digits,
      period: period,
      updatedAt: now(),
    );
  }
}

/// Gộp hai danh sách theo id, giữ bản có [OtpEntry.updatedAt] mới hơn.
List<OtpEntry> mergeEntries(List<OtpEntry> a, List<OtpEntry> b) {
  final byId = <String, OtpEntry>{};
  for (final e in [...a, ...b]) {
    final current = byId[e.id];
    if (current == null || e.updatedAt > current.updatedAt) {
      byId[e.id] = e;
    }
  }
  return byId.values.toList();
}

/// Hai danh sách có cùng tập (id, updatedAt) hay không.
bool sameEntries(List<OtpEntry> a, List<OtpEntry> b) {
  if (a.length != b.length) return false;
  final map = {for (final e in a) e.id: e.updatedAt};
  return b.every((e) => map[e.id] == e.updatedAt);
}
