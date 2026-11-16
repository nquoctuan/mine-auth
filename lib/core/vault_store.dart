import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Lưu file trên máy: vault đã mã hoá và refresh token Drive (cũng đã mã hoá).
class VaultStore {
  VaultStore(this.dir);

  final Directory dir;

  static Future<VaultStore> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return VaultStore(dir);
  }

  File _file(String name) => File('${dir.path}${Platform.pathSeparator}$name');

  File get _vault => _file('vault.json');
  File get _token => _file('drive_token.json');

  Future<bool> vaultExists() => _vault.exists();
  Future<String> readVault() => _vault.readAsString();
  Future<void> writeVault(String content) => _writeAtomic(_vault, content);

  Future<String?> readToken() async =>
      await _token.exists() ? _token.readAsString() : null;
  Future<void> writeToken(String content) => _writeAtomic(_token, content);
  Future<void> deleteToken() async {
    if (await _token.exists()) await _token.delete();
  }

  /// Ghi ra file tạm rồi đổi tên, tránh hỏng vault nếu app bị tắt giữa chừng.
  Future<void> _writeAtomic(File target, String content) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(target.path);
  }
}
