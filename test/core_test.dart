import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mine_auth/core/base32.dart';
import 'package:mine_auth/core/otp_entry.dart';
import 'package:mine_auth/core/totp.dart';
import 'package:mine_auth/core/vault_crypto.dart';

void main() {
  group('base32', () {
    test('giải mã vector RFC 4648', () {
      expect(utf8.decode(base32Decode('MZXW6YTBOI======')), 'foobar');
      expect(utf8.decode(base32Decode('mzxw 6ytb-oi')), 'foobar');
    });

    test('báo lỗi ký tự không hợp lệ', () {
      expect(() => base32Decode('ABC1'), throwsFormatException);
      expect(() => base32Decode(''), throwsFormatException);
    });
  });

  group('TOTP (vector RFC 6238)', () {
    DateTime at(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    final sha1Key = ascii.encode('12345678901234567890');
    final sha256Key = ascii.encode('12345678901234567890123456789012');
    final sha512Key = ascii.encode(
        '1234567890123456789012345678901234567890123456789012345678901234');

    test('SHA1', () {
      expect(generateTotp(secret: sha1Key, time: at(59), digits: 8), '94287082');
      expect(generateTotp(secret: sha1Key, time: at(1111111109), digits: 8), '07081804');
      expect(generateTotp(secret: sha1Key, time: at(20000000000), digits: 8), '65353130');
      expect(generateTotp(secret: sha1Key, time: at(59)), '287082');
    });

    test('SHA256', () {
      expect(
        generateTotp(secret: sha256Key, time: at(59), digits: 8, algorithm: OtpAlgorithm.sha256),
        '46119246',
      );
    });

    test('SHA512', () {
      expect(
        generateTotp(secret: sha512Key, time: at(59), digits: 8, algorithm: OtpAlgorithm.sha512),
        '90693936',
      );
    });
  });

  group('otpauth://', () {
    test('đọc đủ tham số', () {
      final e = OtpEntry.fromUri(
          'otpauth://totp/ACME%20Co:john.doe@email.com?secret=hxdm%20vjec%20jjws%20rb3h&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60');
      expect(e.issuer, 'ACME Co');
      expect(e.account, 'john.doe@email.com');
      expect(e.secret, 'HXDMVJECJJWSRB3H');
      expect(e.algorithm, OtpAlgorithm.sha256);
      expect(e.digits, 8);
      expect(e.period, 60);
    });

    test('mặc định và nhãn không có issuer', () {
      final e = OtpEntry.fromUri('otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP');
      expect(e.issuer, '');
      expect(e.account, 'alice');
      expect(e.digits, 6);
      expect(e.period, 30);
      expect(e.algorithm, OtpAlgorithm.sha1);
    });

    test('từ chối link không hợp lệ', () {
      expect(() => OtpEntry.fromUri('https://example.com'), throwsFormatException);
      expect(() => OtpEntry.fromUri('otpauth://hotp/a?secret=JBSWY3DPEHPK3PXP'), throwsFormatException);
      expect(() => OtpEntry.fromUri('otpauth://totp/a?secret=!!!'), throwsFormatException);
      expect(() => OtpEntry.fromUri('otpauth-migration://offline?data=abc'), throwsFormatException);
    });
  });

  group('gộp khi đồng bộ', () {
    OtpEntry entry(String id, int updatedAt, {bool deleted = false}) => OtpEntry(
        id: id, issuer: id, account: '', secret: 'JBSWY3DPEHPK3PXP', updatedAt: updatedAt, deleted: deleted);

    test('bản mới hơn thắng, việc xoá được giữ lại', () {
      final local = [entry('a', 1), entry('b', 5), entry('c', 1)];
      final remote = [entry('a', 2, deleted: true), entry('b', 3), entry('d', 1)];
      final merged = {for (final e in mergeEntries(local, remote)) e.id: e};
      expect(merged.keys.toSet(), {'a', 'b', 'c', 'd'});
      expect(merged['a']!.deleted, isTrue);
      expect(merged['b']!.updatedAt, 5);
      expect(sameEntries(merged.values.toList(), remote), isFalse);
      expect(sameEntries(local, [...local.reversed]), isTrue);
    });
  });

  group('vault', () {
    // Tham số nhỏ để test chạy nhanh; app thật dùng mặc định của KdfParams.
    const kdf = KdfParams(salt: [1, 2, 3, 4, 5, 6, 7, 8], memory: 64, iterations: 1);
    final entries = [
      const OtpEntry(id: 'x', issuer: 'GitHub', account: 'me', secret: 'JBSWY3DPEHPK3PXP', updatedAt: 42),
    ];

    test('mã hoá rồi giải mã lại đúng dữ liệu', () async {
      final key = await VaultCrypto.keyFor('correct horse', kdf);
      final file = await VaultCrypto.encryptVault(key, entries);
      expect(file.contains('JBSWY3DPEHPK3PXP'), isFalse);
      expect(VaultCrypto.readKdf(file).sameAs(kdf), isTrue);

      final back = await VaultCrypto.decryptVault(key, file);
      expect(back.single.secret, 'JBSWY3DPEHPK3PXP');
      expect(back.single.issuer, 'GitHub');
      expect(back.single.updatedAt, 42);
    });

    test('sai password thì không mở được', () async {
      final key = await VaultCrypto.keyFor('correct horse', kdf);
      final file = await VaultCrypto.encryptVault(key, entries);
      final wrong = await VaultCrypto.keyFor('wrong horse', kdf);
      expect(() => VaultCrypto.decryptVault(wrong, file),
          throwsA(isA<WrongPasswordException>()));
    });

    test('mã hoá chuỗi (refresh token)', () async {
      final key = await VaultCrypto.keyFor('pw', kdf);
      final enc = await VaultCrypto.encryptText(key, 'token-123');
      expect(enc.contains('token-123'), isFalse);
      expect(await VaultCrypto.decryptText(key, enc), 'token-123');
    });
  });
}
