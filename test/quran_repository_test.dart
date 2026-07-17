import 'package:flutter_test/flutter_test.dart';
import 'package:sanad/data/quran_repository.dart';

/// Pins that a FAILED page load is never memoized: before the fix,
/// `_pageFutures.putIfAbsent` cached the already-failed Future forever, so a
/// later `page(p)` call for the same (bad) page returned the SAME failed
/// Future instead of attempting a fresh load -- poisoning that page for the
/// rest of the app run with no way to recover, even if the underlying cause
/// (a transient IO/OOM hiccup) had cleared.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failed page load is not cached -- a later call retries fresh', () async {
    final repo = QuranRepository();
    const badPage = 9999; // no such asset

    final first = repo.page(badPage);
    await expectLater(first, throwsA(anything));

    final second = repo.page(badPage);
    expect(identical(first, second), isFalse,
        reason: 'a retry must be a fresh load attempt, not the memoized failure');
    await expectLater(second, throwsA(anything));
  });

  test('a real page still loads and IS cached (memoization intact for success)',
      () async {
    final repo = QuranRepository();
    final first = repo.page(1);
    final second = repo.page(1);
    expect(identical(first, second), isTrue,
        reason: 'successful loads should still be memoized, only failures are not');
    await first;
    expect(repo.cachedPage(1), isNotNull);
  });
}
