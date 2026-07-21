import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'data/prefs.dart';
import 'data/quran_repository.dart';
import 'services/analytics.dart';
import 'services/asr/asr_engine.dart';
import 'services/asr/word_asr.dart';
import 'state/dhikr_counter_state.dart';
import 'state/reading_state.dart';
import 'state/voice_search_state.dart';
import 'util/log.dart';
import 'screens/root_scaffold.dart';
import 'l10n/app_localizations.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'util/licenses.dart';

/// Single funnel for every crash-reporting path below (FlutterError, the root
/// zone's PlatformDispatcher, and runZonedGuarded) so a native/async error gets
/// the same local log entry + optional consented crash report as a framework
/// build/layout error does.
void _reportError(Object error, StackTrace? stack,
    {String library = 'zone', bool fatal = false}) {
  Log.e(library, error, stack);
  if (Analytics.instance.essentialConsent) {
    Analytics.instance.recordCrash(buildCrashReport(
      error: error.toString(),
      library: library,
      fatal: fatal,
      platform: Platform.operatingSystem,
    ));
  }
}

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    registerThirdPartyLicenses(); // surface bundled model/font/data notices in the license page
    // Dev-only: persist logs to an adb-pullable file. Off in release/store builds
    // so recitation traces never hit disk (build with --dart-define=DIAG=true to
    // re-enable for device debugging).
    if (Log.diagEnabled) await Log.initFileSink();

    // Synchronous Flutter framework errors (build/layout/paint).
    FlutterError.onError = (details) {
      _reportError(details.exceptionAsString(), details.stack,
          library: details.library ?? 'flutter');
      FlutterError.presentError(details);
    };
    // Errors from native/platform-channel callbacks and other root-zone
    // dispatches that never reach FlutterError.onError.
    PlatformDispatcher.instance.onError = (error, stack) {
      _reportError(error, stack, library: 'platform');
      return true;
    };

    final prefs = await Prefs.load();
    Log.d('app', 'start, lastPage=${prefs.lastPage}, theme=${prefs.themeMode}');
    runApp(TilawaApp(prefs: prefs));
  },
      // Uncaught async Future/microtask errors anywhere in the app.
      (error, stack) => _reportError(error, stack, library: 'async'));
}

class TilawaApp extends StatelessWidget {
  final Prefs prefs;
  const TilawaApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState(prefs)),
        Provider<AsrEngine>(create: (_) => AsrEngine(), dispose: (_, e) => e.dispose()),
        ChangeNotifierProvider(create: (ctx) => ReadingState(ctx.read<AsrEngine>())),
        Provider<WordAsr>(create: (_) => WordAsr(), dispose: (_, w) => w.dispose()),
        ChangeNotifierProvider(
            create: (ctx) => VoiceSearchState(ctx.read<AsrEngine>(), ctx.read<WordAsr>())),
        ChangeNotifierProvider(
            create: (ctx) =>
                DhikrCounterState(prefs, ctx.read<AsrEngine>(), ctx.read<WordAsr>())),
        Provider(create: (_) => QuranRepository()),
      ],
      child: Consumer<AppState>(
        builder: (context, app, _) => MaterialApp(
          title: 'Sanad',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(app.accentColor),
          darkTheme: AppTheme.dark(app.accentColor),
          themeMode: app.themeMode,
          // Arabic by default (see Prefs.languageCode) — this also sets the
          // app's text direction to RTL, which is why the reader/list screens
          // no longer need to wrap their Arabic content in Directionality.
          locale: app.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const RootScaffold(),
        ),
      ),
    );
  }
}
