import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/vault_crypto.dart';

class _LockLayout extends StatelessWidget {
  const _LockLayout({required this.title, required this.subtitle, required this.children});

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.shield_outlined, size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(subtitle, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lần chạy đầu: đặt master password.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_password.text.length < 8) {
      setState(() => _error = 'Master password cần ít nhất 8 ký tự');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Hai lần nhập không khớp');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.createVault(_password.text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Không tạo được vault: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _LockLayout(
      title: 'Tạo master password',
      subtitle: 'Mật khẩu này mã hoá toàn bộ mã OTP trên máy và trên Google Drive. '
          'Quên là không khôi phục được. Nếu đã có dữ liệu trên Drive từ máy khác, '
          'hãy đặt đúng master password đã dùng ở máy đó.',
      children: [
        TextField(
          controller: _password,
          obscureText: true,
          autofocus: true,
          enabled: !_busy,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Master password', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirm,
          obscureText: true,
          enabled: !_busy,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Nhập lại',
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Tạo vault'),
        ),
      ],
    );
  }
}

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.state});
  final AppState state;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.unlock(_password.text);
    } on WrongPasswordException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Sai master password';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Không mở được vault: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _LockLayout(
      title: 'Mine Auth',
      subtitle: 'Nhập master password để mở khoá',
      children: [
        TextField(
          controller: _password,
          obscureText: true,
          autofocus: true,
          enabled: !_busy,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Master password',
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Mở khoá'),
        ),
      ],
    );
  }
}
