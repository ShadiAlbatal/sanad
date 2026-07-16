import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa_ai/services/analytics.dart';

/// Pins the opt-in gate: a session reaches the sink ONLY when usage consent is
/// on. This is the single line between "nothing leaves the device" and "a report
/// is emitted", so it is the one that must never silently flip.
class _FakeSink implements AnalyticsSink {
  final List<Map<String, dynamic>> sent = [];
  @override
  Future<void> sendSession(Map<String, dynamic> report) async => sent.add(report);
}

void main() {
  test('consent OFF (default) → sink is never called', () async {
    final sink = _FakeSink();
    final a = Analytics(sink);
    await a.recordSession({'kind': 'quran'});
    expect(sink.sent, isEmpty);
  });

  test('consent ON → sink receives the report once', () async {
    final sink = _FakeSink();
    final a = Analytics(sink)..usageConsent = true;
    await a.recordSession({'kind': 'dua', 'duaId': 'x'});
    expect(sink.sent, hasLength(1));
    expect(sink.sent.single['duaId'], 'x');
  });

  test('flipping consent back OFF stops sending again', () async {
    final sink = _FakeSink();
    final a = Analytics(sink)..usageConsent = true;
    await a.recordSession({'n': 1});
    a.usageConsent = false;
    await a.recordSession({'n': 2});
    expect(sink.sent, hasLength(1));
    expect(sink.sent.single['n'], 1);
  });

  test('the two gates are independent: essential gates crashes, not sessions', () async {
    final sink = _FakeSink();
    // essential ON, usage OFF
    final a = Analytics(sink)..essentialConsent = true;
    await a.recordCrash({'kind': 'crash'});
    await a.recordSession({'kind': 'quran'}); // usage still off → dropped
    expect(sink.sent, hasLength(1));
    expect(sink.sent.single['kind'], 'crash');
  });

  test('essential OFF (default) → crash is never sent', () async {
    final sink = _FakeSink();
    final a = Analytics(sink)..usageConsent = true; // usage on, essential off
    await a.recordCrash({'kind': 'crash'});
    expect(sink.sent, isEmpty);
  });
}
