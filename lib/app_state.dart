import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core/otp_entry.dart';
import 'core/vault_crypto.dart';
import 'core/vault_store.dart';
import 'sync/google_drive.dart';

enum AppStage { needsSetup, locked, unlocked }

enum SyncStatus { off, idle, syncing, error }

class AppState extends ChangeNotifier {
  AppState(this._store);

  final VaultStore _store;

  AppStage stage = AppStage.locked;
  SyncStatus syncStatus = SyncStatus.off;
  String? syncError;
  DateTime? lastSync;

  List<OtpEntry> _all = [];
  VaultKey? _key;
  String? _password;
  GoogleDriveSync? _drive;
  bool _syncAgain = false;

  bool get driveConnected => _drive != null;

  /// Các tài khoản đang dùng (bỏ bản ghi đã xoá), sắp theo tên.
  List<OtpEntry> get entries {
    final list = _all.where((e) => !e.deleted).toList();
    list.sort((a, b) {
      final c = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return c != 0 ? c : a.account.toLowerCase().compareTo(b.account.toLowerCase());
    });
    return list;
  }

  Future<void> init() async {
    stage = await _store.vaultExists() ? AppStage.locked : AppStage.needsSetup;
    notifyListeners();
  }

  Future<void> createVault(String password) async {
    _key = await VaultCrypto.createKey(password);
    _password = password;
    _all = [];
    await _saveLocal();
    stage = AppStage.unlocked;
    notifyListeners();
  }

  /// Ném [WrongPasswordException] nếu sai password.
  Future<void> unlock(String password) async {
    final content = await _store.readVault();
    final key = await VaultCrypto.keyFor(password, VaultCrypto.readKdf(content));
    _all = await VaultCrypto.decryptVault(key, content);
    _key = key;
    _password = password;

    final token = await _store.readToken();
    if (token != null) {
      try {
        _drive = GoogleDriveSync(refreshToken: await VaultCrypto.decryptText(key, token));
        syncStatus = SyncStatus.idle;
      } catch (_) {
        await _store.deleteToken();
      }
    }
    stage = AppStage.unlocked;
    notifyListeners();
    unawaited(sync());
  }

  void lock() {
    _all = [];
    _key = null;
    _password = null;
    _drive = null;
    syncStatus = SyncStatus.off;
    syncError = null;
    stage = AppStage.locked;
    notifyListeners();
  }

  Future<void> save(OtpEntry entry) async {
    final updated = entry.copyWith(updatedAt: OtpEntry.now());
    _all = [..._all.where((e) => e.id != entry.id), updated];
    await _changed();
  }

  Future<void> delete(String id) async {
    _all = [
      for (final e in _all)
        if (e.id == id)
          e.copyWith(deleted: true, secret: '', updatedAt: OtpEntry.now())
        else
          e,
    ];
    await _changed();
  }

  Future<void> _changed() async {
    await _saveLocal();
    notifyListeners();
    unawaited(sync());
  }

  Future<void> _saveLocal() async =>
      _store.writeVault(await VaultCrypto.encryptVault(_key!, _all));

  Future<void> _saveToken() async {
    final token = _drive?.refreshToken;
    if (token != null) {
      await _store.writeToken(await VaultCrypto.encryptText(_key!, token));
    }
  }

  /// Mở trình duyệt đăng nhập Google rồi đồng bộ lần đầu.
  Future<void> connectDrive() async {
    final drive = GoogleDriveSync();
    await drive.signIn();
    if (stage != AppStage.unlocked) return;
    _drive = drive;
    await _saveToken();
    syncStatus = SyncStatus.idle;
    notifyListeners();
    await sync();
  }

  Future<void> disconnectDrive() async {
    _drive = null;
    await _store.deleteToken();
    syncStatus = SyncStatus.off;
    syncError = null;
    notifyListeners();
  }

  /// Tải vault trên Drive, gộp với bản trên máy (bản sửa mới hơn thắng), rồi đẩy lên lại.
  Future<void> sync() async {
    final drive = _drive;
    if (drive == null || stage != AppStage.unlocked) return;
    if (syncStatus == SyncStatus.syncing) {
      _syncAgain = true;
      return;
    }
    syncStatus = SyncStatus.syncing;
    syncError = null;
    notifyListeners();

    bool stillActive() => stage == AppStage.unlocked && identical(_drive, drive);

    try {
      final remote = await drive.download();
      if (!stillActive()) return;

      var needUpload = true;
      if (remote != null) {
        // Máy khác có thể đã tạo vault với salt khác: sinh lại khoá theo salt trên Drive
        // rồi dùng luôn khoá đó cho máy này để các máy hội tụ về một khoá.
        final remoteKdf = VaultCrypto.readKdf(remote);
        var key = _key!;
        final keyChanged = !remoteKdf.sameAs(key.kdf);
        if (keyChanged) {
          key = await VaultCrypto.keyFor(_password!, remoteKdf);
        }
        final List<OtpEntry> remoteEntries;
        try {
          remoteEntries = await VaultCrypto.decryptVault(key, remote);
        } on WrongPasswordException {
          throw DriveException(
              'Master password của máy này khác với vault trên Drive. '
              'Hãy dùng cùng master password trên mọi máy.');
        }
        if (!stillActive()) return;

        final merged = mergeEntries(_all, remoteEntries);
        needUpload = !sameEntries(merged, remoteEntries);
        final localChanged = keyChanged || !sameEntries(merged, _all);
        _key = key;
        _all = merged;
        if (localChanged) {
          await _saveLocal();
          if (keyChanged) await _saveToken();
        }
      }
      if (needUpload) {
        await drive.upload(await VaultCrypto.encryptVault(_key!, _all));
      }
      if (!stillActive()) return;
      lastSync = DateTime.now();
      syncStatus = SyncStatus.idle;
    } catch (e) {
      if (!stillActive()) return;
      syncStatus = SyncStatus.error;
      syncError = e.toString();
    } finally {
      if (syncStatus == SyncStatus.syncing) {
        // Bị khoá / ngắt kết nối giữa chừng.
        syncStatus = _drive == null ? SyncStatus.off : SyncStatus.idle;
      }
      notifyListeners();
    }

    if (_syncAgain) {
      _syncAgain = false;
      unawaited(sync());
    }
  }
}
