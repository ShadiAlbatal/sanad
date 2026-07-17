import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/services/asr/asr_engine.dart';

/// Pins the single-owner-mic contract ([MicOwnership]) — the mechanism behind
/// the device-confirmed dua-reader degradation fix (one shared engine + one mic
/// whose new claimant preempts the previous session). AsrEngine itself holds a
/// MicSource/AudioRecorder (a platform channel) and can't be constructed under
/// `flutter test`, so the ownership logic was extracted here to pin it directly.
void main() {
  late MicOwnership owner;
  late List<String> released;
  Future<void> Function() releaser(String id) => () async => released.add(id);

  setUp(() {
    owner = MicOwnership();
    released = [];
  });

  test('first claim owns the mic without releasing anything', () async {
    await owner.claim(releaser('A'));
    expect(released, isEmpty);
  });

  test('a new claimant preempts the previous owner exactly once', () async {
    final a = releaser('A');
    await owner.claim(a);
    await owner.claim(releaser('B'));
    expect(released, ['A']);
  });

  test('re-claiming with the same callback does NOT stop self', () async {
    final a = releaser('A');
    await owner.claim(a);
    await owner.claim(a);
    expect(released, isEmpty);
  });

  test('release by the active owner vacates the slot (next claim stops nobody)', () async {
    final a = releaser('A');
    await owner.claim(a);
    owner.release(a);
    await owner.claim(releaser('B'));
    expect(released, isEmpty);
  });

  test('release by a non-owner is a no-op — the owner still gets preempted later', () async {
    await owner.claim(releaser('A'));
    owner.release(releaser('B')); // different identity → ignored
    await owner.claim(releaser('C'));
    expect(released, ['A']);
  });

  test('a stale release cannot clear the current owner', () async {
    final a = releaser('A');
    await owner.claim(a);
    await owner.claim(releaser('B')); // A preempted, B now owns
    owner.release(a); // A is stale — must not clear B
    await owner.claim(releaser('C'));
    expect(released, ['A', 'B']);
  });

  test('preempting awaits a slow release before the new owner is active', () async {
    final gate = Completer<void>();
    final order = <String>[];
    Future<void> slowA() async {
      await gate.future;
      order.add('A-released');
    }

    await owner.claim(slowA);
    final claimB = owner.claim(() async => order.add('B-released')).then((_) => order.add('B-active'));

    await Future<void>.delayed(Duration.zero);
    expect(order, isEmpty, reason: 'claim must block on the slow release');

    gate.complete();
    await claimB;
    expect(order, ['A-released', 'B-active']);
  });
}
