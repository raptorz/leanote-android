import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SharedText {
  SharedText({
    required this.id,
    required this.title,
    required this.text,
    this.accountKey = '',
  }) {
    if (!RegExp(r'^[0-9a-f]{24}$').hasMatch(id) ||
        text.trim().isEmpty ||
        text.contains('\u0000') ||
        utf8.encode(text).length > 256 * 1024) {
      throw const FormatException('分享文本无效或超过 256 KiB');
    }
  }
  final String id;
  final String title;
  final String text;
  final String accountKey;

  factory SharedText.fromMap(Map<Object?, Object?> map) => SharedText(
    id: map['id'] as String,
    title: map['title'] as String? ?? '',
    text: map['text'] as String,
    accountKey: map['accountKey'] as String? ?? '',
  );

  String get suggestedTitle {
    final source = title.trim().isEmpty ? text.split('\n').first : title;
    final clean = source.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    return clean.isEmpty
        ? '分享的笔记'
        : String.fromCharCodes(clean.runes.take(200));
  }
}

/// Android owns the durable queue, including while Flutter is on the login page.
/// Entries are acknowledged only after import or explicit discard.
class SharedTextInbox extends ChangeNotifier {
  SharedTextInbox({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('gemsnote/shared_text'),
      supported =
          supported ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  final MethodChannel _channel;
  final bool supported;
  SharedText? pending;
  String? error;
  bool _disposed = false;
  int _generation = 0;

  Future<void> start() async {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') await refresh();
    });
    await refresh();
  }

  Future<void> refresh() async {
    if (!supported || _disposed) return;
    final generation = ++_generation;
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>('peek');
      if (_disposed || generation != _generation) return;
      pending = value == null ? null : SharedText.fromMap(value);
      error = null;
    } on MissingPluginException {
      // Other platforms and widget-only hosts do not register this channel.
      return;
    } on Object catch (failure) {
      if (_disposed || generation != _generation) return;
      error = '读取待处理分享失败：$failure';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> claim(SharedText item, String accountKey) => _channel
      .invokeMethod<void>('claim', {'id': item.id, 'accountKey': accountKey});

  Future<void> acknowledge(SharedText item) async {
    await _channel.invokeMethod<void>('acknowledge', {'id': item.id});
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    if (supported) _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
