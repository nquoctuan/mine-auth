import 'dart:typed_data';

const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Chuẩn hoá secret: bỏ khoảng trắng, gạch nối, dấu '=' và viết hoa.
String normalizeBase32(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[\s\-=]'), '');

/// Giải mã Base32 (RFC 4648). Ném [FormatException] nếu có ký tự không hợp lệ.
Uint8List base32Decode(String input) {
  final clean = normalizeBase32(input);
  if (clean.isEmpty) {
    throw const FormatException('Secret trống');
  }
  final out = BytesBuilder();
  var buffer = 0;
  var bits = 0;
  for (var i = 0; i < clean.length; i++) {
    final v = _alphabet.indexOf(clean[i]);
    if (v < 0) {
      throw FormatException('Ký tự không hợp lệ trong secret: "${clean[i]}"');
    }
    buffer = (buffer << 5) | v;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.addByte((buffer >> bits) & 0xff);
      buffer &= (1 << bits) - 1;
    }
  }
  return out.toBytes();
}
