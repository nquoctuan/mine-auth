import 'dart:typed_data';

import 'package:crypto/crypto.dart';

enum OtpAlgorithm { sha1, sha256, sha512 }

/// Sinh mã TOTP theo RFC 6238.
String generateTotp({
  required List<int> secret,
  required DateTime time,
  int period = 30,
  int digits = 6,
  OtpAlgorithm algorithm = OtpAlgorithm.sha1,
}) {
  var counter = time.millisecondsSinceEpoch ~/ 1000 ~/ period;
  final message = Uint8List(8);
  for (var i = 7; i >= 0; i--) {
    message[i] = counter & 0xff;
    counter >>= 8;
  }

  final Hash hash = switch (algorithm) {
    OtpAlgorithm.sha1 => sha1,
    OtpAlgorithm.sha256 => sha256,
    OtpAlgorithm.sha512 => sha512,
  };
  final mac = Hmac(hash, secret).convert(message).bytes;

  final offset = mac[mac.length - 1] & 0x0f;
  final binary = ((mac[offset] & 0x7f) << 24) |
      (mac[offset + 1] << 16) |
      (mac[offset + 2] << 8) |
      mac[offset + 3];

  var modulo = 1;
  for (var i = 0; i < digits; i++) {
    modulo *= 10;
  }
  return (binary % modulo).toString().padLeft(digits, '0');
}
