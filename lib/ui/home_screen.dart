import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/otp_entry.dart';
import '../oauth_config.dart';
import 'edit_screen.dart';
import 'scan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state});
  final AppState state;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _timer;
  DateTime _now = DateTime.now();
  String _query = '';

  AppState get _state => widget.state;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy(OtpEntry entry) async {
    try {
      await Clipboard.setData(ClipboardData(text: entry.codeAt(DateTime.now())));
      _toast('Đã copy mã ${entry.title}');
    } on FormatException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _addFromUri(String raw) async {
    try {
      final entry = OtpEntry.fromUri(raw);
      await _state.save(entry);
      _toast('Đã thêm ${entry.title}');
    } on FormatException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _scan() async {
    final value = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (value != null) await _addFromUri(value);
  }

  Future<void> _edit([OtpEntry? entry]) async {
    final result = await Navigator.of(context)
        .push<OtpEntry>(MaterialPageRoute(builder: (_) => EditScreen(entry: entry)));
    if (result != null) await _state.save(result);
  }

  Future<void> _pasteUri() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dán link otpauth://'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'otpauth://totp/...?secret=...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
    if (value != null && value.trim().isNotEmpty) await _addFromUri(value);
  }

  Future<void> _confirmDelete(OtpEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Xoá ${entry.title}?'),
        content: const Text(
            'Mã OTP của tài khoản này sẽ bị xoá trên mọi máy đã đồng bộ. '
            'Hãy chắc chắn bạn đã tắt 2FA hoặc có cách đăng nhập khác.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xoá')),
        ],
      ),
    );
    if (ok == true) await _state.delete(entry.id);
  }

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (Platform.isAndroid)
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Quét mã QR'),
                onTap: () {
                  Navigator.pop(sheet);
                  _scan();
                },
              ),
            ListTile(
              leading: const Icon(Icons.keyboard_outlined),
              title: const Text('Nhập secret key'),
              onTap: () {
                Navigator.pop(sheet);
                _edit();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Dán link otpauth://'),
              onTap: () {
                Navigator.pop(sheet);
                _pasteUri();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _connectDrive() async {
    try {
      await _state.connectDrive();
    } catch (e) {
      _toast('$e');
    }
  }

  void _showSyncSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => ListenableBuilder(
        listenable: _state,
        builder: (context, _) {
          final theme = Theme.of(context);
          final String status;
          if (!_state.driveConnected) {
            status = OAuthConfig.isConfigured
                ? 'Chưa kết nối. Dữ liệu chỉ nằm trên máy này.'
                : 'Chưa cấu hình GOOGLE_CLIENT_ID lúc build (xem README).';
          } else {
            status = switch (_state.syncStatus) {
              SyncStatus.syncing => 'Đang đồng bộ…',
              SyncStatus.error => 'Lỗi: ${_state.syncError}',
              _ => _state.lastSync == null
                  ? 'Đã kết nối'
                  : 'Đồng bộ lần cuối lúc ${TimeOfDay.fromDateTime(_state.lastSync!).format(context)}',
            };
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Đồng bộ Google Drive', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(status),
                  const SizedBox(height: 4),
                  Text(
                    'File trên Drive luôn được mã hoá bằng master password.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  if (!_state.driveConnected)
                    FilledButton.icon(
                      onPressed: OAuthConfig.isConfigured ? _connectDrive : null,
                      icon: const Icon(Icons.cloud_outlined),
                      label: const Text('Kết nối Google Drive'),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed:
                          _state.syncStatus == SyncStatus.syncing ? null : _state.sync,
                      icon: const Icon(Icons.sync),
                      label: const Text('Đồng bộ ngay'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _state.disconnectDrive,
                      child: const Text('Ngắt kết nối'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData get _syncIcon => switch (_state.syncStatus) {
        SyncStatus.off => Icons.cloud_off_outlined,
        SyncStatus.idle => Icons.cloud_done_outlined,
        SyncStatus.syncing => Icons.cloud_sync_outlined,
        SyncStatus.error => Icons.cloud_off,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final entries = _state.entries
        .where((e) =>
            query.isEmpty ||
            e.issuer.toLowerCase().contains(query) ||
            e.account.toLowerCase().contains(query))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mine Auth'),
        actions: [
          IconButton(
            tooltip: 'Đồng bộ Google Drive',
            onPressed: _showSyncSheet,
            icon: Icon(
              _syncIcon,
              color: _state.syncStatus == SyncStatus.error ? theme.colorScheme.error : null,
            ),
          ),
          IconButton(
            tooltip: 'Khoá',
            onPressed: _state.lock,
            icon: const Icon(Icons.lock_outline),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        tooltip: 'Thêm tài khoản',
        child: const Icon(Icons.add),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              if (_state.entries.length > 5)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Tìm tài khoản',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _state.entries.isEmpty
                                ? 'Chưa có tài khoản nào.\nBấm + để thêm.'
                                : 'Không tìm thấy tài khoản phù hợp.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) => _EntryTile(
                          entry: entries[i],
                          now: _now,
                          onCopy: () => _copy(entries[i]),
                          onEdit: () => _edit(entries[i]),
                          onDelete: () => _confirmDelete(entries[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.now,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
  });

  final OtpEntry entry;
  final DateTime now;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String code;
    try {
      code = entry.codeAt(now);
      final half = code.length ~/ 2;
      code = '${code.substring(0, half)} ${code.substring(half)}';
    } on FormatException {
      code = 'Secret lỗi';
    }

    final seconds = now.millisecondsSinceEpoch ~/ 1000;
    final remaining = entry.period - seconds % entry.period;
    final urgent = remaining <= 5;
    final color = urgent ? theme.colorScheme.error : theme.colorScheme.primary;

    return InkWell(
      onTap: onCopy,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.issuer.isNotEmpty && entry.account.isNotEmpty
                        ? '${entry.issuer} · ${entry.account}'
                        : entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    code,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: remaining / entry.period,
                    strokeWidth: 3,
                    color: color,
                  ),
                  Text('$remaining', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') {
                  onEdit();
                } else if (v == 'delete') {
                  onDelete();
                } else {
                  onCopy();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'copy', child: Text('Copy mã')),
                PopupMenuItem(value: 'edit', child: Text('Sửa')),
                PopupMenuItem(value: 'delete', child: Text('Xoá')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
