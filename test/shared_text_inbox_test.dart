import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gemsnote/services/shared_text_inbox.dart';

const id = '507f1f77bcf86cd799439012';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gemsnote/shared_text_test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform reads a durable share on start and resume', () async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var body = 'cold start';
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'id': id, 'text': body, 'accountKey': 'server/user'},
      );
      final inbox = SharedTextInbox(channel: channel);
      addTearDown(inbox.dispose);
      expect(inbox.supported, isTrue);
      await inbox.start();
      expect(inbox.pending!.text, 'cold start');
      expect(inbox.pending!.accountKey, 'server/user');
      body = 'share received while app was backgrounded';
      await inbox.refresh();
      expect(inbox.pending!.text, body);
    });
  }

  test('validates byte limit, IDs and binary data without interpreting URLs or HTML', () {
    for (final content in ['', '  ', 'a\u0000b', '中' * 90000]) {
      expect(
        () => SharedText(id: id, title: '', text: content),
        throwsFormatException,
      );
    }
    expect(
      () => SharedText(id: 'invalid', title: '', text: 'text'),
      throwsFormatException,
    );
    final share = SharedText(
      id: id,
      title: '  My\nTitle ',
      text: '<script>x</script>\nhttps://example.test',
    );
    expect(share.suggestedTitle, 'MyTitle');
    expect(share.text, '<script>x</script>\nhttps://example.test');
    expect(
      SharedText(
        id: id,
        title: '',
        text: '😀' * 300,
      ).suggestedTitle.runes.length,
      200,
    );
  });

  test(
    'peek does not consume; claim and acknowledge use exact ID and account',
    () async {
      final calls = <MethodCall>[];
      var acknowledged = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'peek') {
          return acknowledged
              ? null
              : {'id': id, 'text': 'body', 'title': 'title', 'accountKey': ''};
        }
        if (call.method == 'acknowledge') acknowledged = true;
        return null;
      });
      final inbox = SharedTextInbox(channel: channel, supported: true);
      addTearDown(inbox.dispose);
      await inbox.start();
      expect(inbox.pending!.text, 'body');
      expect(calls.map((c) => c.method), ['peek']);
      final source = inbox.pending!;
      await inbox.claim(source, 'account');
      expect(calls.last.arguments, {'id': id, 'accountKey': 'account'});
      await inbox.acknowledge(source);
      expect(calls[calls.length - 2].arguments, {'id': id});
      expect(inbox.pending, isNull);
    },
  );

  test(
    'failed acknowledgement retains entry; refresh errors are recoverable',
    () async {
      var fail = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (fail || call.method == 'acknowledge') {
          throw PlatformException(code: 'disk');
        }
        return {'id': id, 'text': 'body', 'title': ''};
      });
      final inbox = SharedTextInbox(channel: channel, supported: true);
      addTearDown(inbox.dispose);
      await inbox.start();
      await expectLater(
        inbox.acknowledge(inbox.pending!),
        throwsA(isA<PlatformException>()),
      );
      expect(inbox.pending!.id, id);
      fail = true;
      await inbox.refresh();
      expect(inbox.error, isNotNull);
      fail = false;
      await inbox.refresh();
      expect(inbox.error, isNull);
    },
  );

  test(
    'stale refresh and callbacks after disposal cannot replace newer state',
    () async {
      final old = Completer<Map<String, String>>();
      var reads = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        reads++;
        if (reads == 1) return old.future;
        return {'id': id, 'text': 'new', 'title': ''};
      });
      final inbox = SharedTextInbox(channel: channel, supported: true);
      final first = inbox.start();
      await Future<void>.delayed(Duration.zero);
      await inbox.refresh();
      old.complete({'id': id, 'text': 'old', 'title': ''});
      await first;
      expect(inbox.pending!.text, 'new');
      inbox.dispose();
      await inbox.refresh();
      expect(reads, 2);
    },
  );

  test(
    'disposing old workspace does not remove the new share handler',
    () async {
      var body = 'old';
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'id': id, 'text': body},
      );
      final old = SharedTextInbox(channel: channel, supported: true);
      final next = SharedTextInbox(channel: channel, supported: true);
      await old.start();
      await next.start();
      old.dispose();
      body = 'new';
      final delivered = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.channelBuffers.push(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('changed'),
        ),
        (_) => delivered.complete(),
      );
      await delivered.future;
      expect(next.pending!.text, 'new');
      next.dispose();
    },
  );

  test('unsupported platforms do not invoke native methods', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw StateError('unexpected'),
    );
    final inbox = SharedTextInbox(channel: channel, supported: false);
    await inbox.start();
    await inbox.refresh();
    inbox.dispose();
  });
}
