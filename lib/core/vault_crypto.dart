import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'otp_entry.dart';

class WrongPasswordException implements Exception {
  const WrongPasswordException();
  @override
  String toString() => 'Sai master password';
}

/// Tham số Argon2id. [memory] tính bằng KiB.
class KdfParams {
  const KdfParams({
    required this.salt,
    this.memory = 19456,
    this.iterations = 2,
    this.parallelism = 1,
  });

  final List<int> salt;
  final int memory;
  final int iterations;
  final int parallelism;

  bool sameAs(KdfParams o) =>
      listEquals(salt, o.salt) &&
      memory == o.memory &&
      iterations == o.iterations &&
      parallelism == o.parallelism;

  Map<String, dynamic> toJson() => {
        'alg': 'argon2id',
        'salt': base64Encode(salt),
        'm': memory,
        't': iterations,
        'p': parallelism,
      };

  factory KdfParams.fromJson(Map<String, dynamic> json) {
    if (json['alg'] != 'argon2id') {
      throw const FormatException('KDF không được hỗ trợ');
    }
    return KdfParams(
      salt: base64Decode(json['salt'] as String),
      memory: json['m'] as int,
      iterations: json['t'] as int,
      parallelism: json['p'] as int,
    );
  }
}

/// Khoá AES-256 kèm tham số KDF đã sinh ra nó.
class VaultKey {
  const VaultKey(this.bytes, this.kdf);
  final List<int> bytes;
  final KdfParams kdf;
}

Future<List<int>> _deriveInIsolate(Map<String, dynamic> args) async {
  final algorithm = Argon2id(
    parallelism: args['p'] as int,
    memory: args['m'] as int,
    iterations: args['t'] as int,
    hashLength: 32,
  );
  final key = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(args['password'] as String)),
    nonce: args['salt'] as List<int>,
  );
  return key.extractBytes();
}

/// Mã hoá vault: Argon2id (master password -> khoá) + AES-256-GCM.
class VaultCrypto {
  static const _format = 'mine-auth-vault';
  static final _aes = AesGcm.with256bits();

  static List<int> randomBytes(int n) {
    final rnd = Random.secure();
    return List<int>.generate(n, (_) => rnd.nextInt(256));
  }

  /// Sinh khoá mới với salt ngẫu nhiên (dùng khi tạo vault).
  static Future<VaultKey> createKey(String password, {KdfParams? params}) =>
      keyFor(password, params ?? KdfParams(salt: randomBytes(16)));

  /// Sinh khoá từ password theo tham số KDF có sẵn. Chạy ở isolate riêng để không đơ UI.
  static Future<VaultKey> keyFor(String password, KdfParams kdf) async {
    final bytes = await compute(_deriveInIsolate, <String, dynamic>{
      'password': password,
      'salt': kdf.salt,
      'm': kdf.memory,
      't': kdf.iterations,
      'p': kdf.parallelism,
    });
    return VaultKey(bytes, kdf);
  }

  static Future<Map<String, dynamic>> _seal(List<int> key, List<int> clear) async {
    final box = await _aes.encrypt(
      clear,
      secretKey: SecretKey(key),
      nonce: _aes.newNonce(),
    );
    return {
      'nonce': base64Encode(box.nonce),
      'ct': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  static Future<List<int>> _open(List<int> key, Map<String, dynamic> json) async {
    final box = SecretBox(
      base64Decode(json['ct'] as String),
      nonce: base64Decode(json['nonce'] as String),
      mac: Mac(base64Decode(json['mac'] as String)),
    );
    try {
      return await _aes.decrypt(box, secretKey: SecretKey(key));
    } on SecretBoxAuthenticationError {
      throw const WrongPasswordException();
    }
  }

  /// Đọc tham số KDF từ nội dung file vault (không cần password).
  static KdfParams readKdf(String fileContent) {
    final json = jsonDecode(fileContent) as Map<String, dynamic>;
    if (json['format'] != _format) {
      throw const FormatException('Không phải file vault của Mine Auth');
    }
    return KdfParams.fromJson(json['kdf'] as Map<String, dynamic>);
  }

  static Future<String> encryptVault(VaultKey key, List<OtpEntry> entries) async {
    final clear = utf8.encode(jsonEncode({
      'entries': [for (final e in entries) e.toJson()],
    }));
    return jsonEncode({
      'format': _format,
      'v': 1,
      'kdf': key.kdf.toJson(),
      ...await _seal(key.bytes, clear),
    });
  }

  /// Ném [WrongPasswordException] nếu khoá sai hoặc file bị sửa đổi.
  static Future<List<OtpEntry>> decryptVault(VaultKey key, String fileContent) async {
    final json = jsonDecode(fileContent) as Map<String, dynamic>;
    final clear = await _open(key.bytes, json);
    final data = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    return [
      for (final e in data['entries'] as List)
        OtpEntry.fromJson(e as Map<String, dynamic>),
    ];
  }

  /// Mã hoá một chuỗi nhỏ (vd. refresh token) bằng khoá vault.
  static Future<String> encryptText(VaultKey key, String text) async =>
      jsonEncode(await _seal(key.bytes, utf8.encode(text)));

  static Future<String> decryptText(VaultKey key, String content) async => utf8.decode(
      await _open(key.bytes, jsonDecode(content) as Map<String, dynamic>));
}
