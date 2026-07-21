import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/util/log.dart';

/// [Log.t] is the recitation firehose — it fires once per matcher apply(),
/// 10-25x/sec for a whole session. A store build has no file sink and no Debug
/// Log screen, so none of it is readable there and none of it should be built.
void main() {
  final saved = Log.traceOn;
  tearDown(() => Log.traceOn = saved);

  test('trace does not build its message when tracing is off', () {
    var built = 0;
    Log.traceOn = false;
    Log.t('test', () {
      built++;
      return 'expensive $built';
    });
    expect(built, 0, reason: 'the builder must not run at all');

    Log.traceOn = true;
    Log.t('test', () {
      built++;
      return 'expensive $built';
    });
    expect(built, 1);
  });

  test('trace follows diagEnabled by default', () {
    // Host tests run in debug, where diagnostics (and so tracing) are on; a
    // release build flips both off together.
    expect(saved, Log.diagEnabled);
  });
}
