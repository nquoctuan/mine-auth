import 'package:flutter/material.dart';

import '../core/base32.dart';
import '../core/otp_entry.dart';
import '../core/totp.dart';

/// Thêm tay hoặc sửa một tài khoản. Trả về [OtpEntry] qua Navigator.pop.
class EditScreen extends StatefulWidget {
  const EditScreen({super.key, this.entry});
  final OtpEntry? entry;

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  final _form = GlobalKey<FormState>();
  late final _issuer = TextEditingController(text: widget.entry?.issuer ?? '');
  late final _account = TextEditingController(text: widget.entry?.account ?? '');
  late final _secret = TextEditingController(text: widget.entry?.secret ?? '');
  late OtpAlgorithm _algorithm = widget.entry?.algorithm ?? OtpAlgorithm.sha1;
  late int _digits = widget.entry?.digits ?? 6;
  late int _period = widget.entry?.period ?? 30;

  @override
  void dispose() {
    _issuer.dispose();
    _account.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final base = widget.entry;
    Navigator.of(context).pop(OtpEntry(
      id: base?.id ?? OtpEntry.newId(),
      issuer: _issuer.text.trim(),
      account: _account.text.trim(),
      secret: normalizeBase32(_secret.text),
      algorithm: _algorithm,
      digits: _digits,
      period: _period,
      updatedAt: OtpEntry.now(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? 'Thêm tài khoản' : 'Sửa tài khoản'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Lưu')),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _issuer,
                  decoration: const InputDecoration(
                      labelText: 'Dịch vụ (vd. GitHub)', border: border),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _account,
                  decoration: const InputDecoration(
                      labelText: 'Tài khoản (email / username)', border: border),
                  textInputAction: TextInputAction.next,
                  validator: (v) => (v ?? '').trim().isEmpty && _issuer.text.trim().isEmpty
                      ? 'Nhập tên dịch vụ hoặc tài khoản'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _secret,
                  decoration: const InputDecoration(
                      labelText: 'Secret key (Base32)', border: border),
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: (v) {
                    try {
                      base32Decode(v ?? '');
                      return null;
                    } on FormatException catch (e) {
                      return e.message;
                    }
                  },
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  title: const Text('Nâng cao'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
                  children: [
                    DropdownButtonFormField<OtpAlgorithm>(
                      // `value` chạy được trên cả Flutter cũ lẫn mới.
                      // ignore: deprecated_member_use
                      value: _algorithm,
                      decoration: const InputDecoration(labelText: 'Thuật toán', border: border),
                      items: [
                        for (final a in OtpAlgorithm.values)
                          DropdownMenuItem(value: a, child: Text(a.name.toUpperCase())),
                      ],
                      onChanged: (v) => setState(() => _algorithm = v ?? _algorithm),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      // `value` chạy được trên cả Flutter cũ lẫn mới.
                      // ignore: deprecated_member_use
                      value: _digits,
                      decoration: const InputDecoration(labelText: 'Số chữ số', border: border),
                      items: const [
                        DropdownMenuItem(value: 6, child: Text('6')),
                        DropdownMenuItem(value: 7, child: Text('7')),
                        DropdownMenuItem(value: 8, child: Text('8')),
                      ],
                      onChanged: (v) => setState(() => _digits = v ?? _digits),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      // `value` chạy được trên cả Flutter cũ lẫn mới.
                      // ignore: deprecated_member_use
                      value: _period,
                      decoration: const InputDecoration(labelText: 'Chu kỳ (giây)', border: border),
                      items: [
                        for (final p in {30, 60, _period})
                          DropdownMenuItem(value: p, child: Text('$p')),
                      ],
                      onChanged: (v) => setState(() => _period = v ?? _period),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
