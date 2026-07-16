import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'asr/session.dart' show RecitationMistake;
import '../util/log.dart';

/// Where end-of-session recitation reports go. Anonymous only — a random
/// per-install id, never any account/PII. See `supabase/sessions.sql` for the
/// table this is designed to feed.
abstract class AnalyticsSink {
  Future<void> sendSession(Map<String, dynamic> report);
}

/// App build id sent with each report (coarse — no device model without a
/// device_info package). Keep in sync with pubspec `version:`.
const appBuildId = '1.0.0+1';

/// The only fields a mistake contributes to a report: category + reference vs
/// heard letters. NEVER the audio sample range (`startSample`/`endSample`) or
/// per-phoneme scores — those stay device-local for playback only.
Map<String, dynamic> slimMistake(RecitationMistake m) => {
      'kind': m.kind.name,
      'loc': m.location,
      'expected': m.expectedText,
      'heard': m.heardText,
    };

/// Builds the anonymous end-of-session report from the primitives the recitation
/// pipeline already has at Stop. PURE — no I/O, no platform channel — and it can
/// only ever emit the fields listed here, so raw audio / PII cannot leak in by
/// construction (the guarantee `test/analytics_report_test.dart` pins). `ref` is
/// the surah number (quran) or du'a id (dua).
Map<String, dynamic> buildSessionReport({
  required String kind, // 'quran' | 'dua'
  required String ref,
  required int reached,
  required int tokens,
  required bool anchored,
  required int skipped,
  required List<RecitationMistake> mistakes,
  required int durationMs,
  required String platform,
  String app = appBuildId,
}) {
  return {
    'schema': 1,
    'kind': kind,
    if (kind == 'quran') 'surah': int.tryParse(ref) else 'duaId': ref,
    'reached': reached,
    'tokens': tokens,
    'anchored': anchored,
    'skipped': skipped,
    'mistakeCount': mistakes.length,
    'mistakes': [for (final m in mistakes) slimMistake(m)],
    'durationMs': durationMs,
    'app': app,
    'platform': platform,
  };
}

/// Builds the anonymous crash/error summary for the "Essential app data"
/// (crash-safety) opt-in. PURE — carries only the error message, where it came
/// from, and coarse app/platform, all clipped. NO stack (may embed paths), NO
/// user data, NO audio. Distinct from the raw `Log.e` capture, which stays a
/// local dev diagnostic regardless of consent.
Map<String, dynamic> buildCrashReport({
  required String error,
  required String library,
  required bool fatal,
  required String platform,
  String app = appBuildId,
}) {
  String clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';
  return {
    'schema': 1,
    'kind': 'crash',
    'error': clip(error.trim(), 300),
    'library': clip(library.trim(), 80),
    'fatal': fatal,
    'app': app,
    'platform': platform,
  };
}

/// The single app-wide analytics gateway: holds the sink and the two opt-in
/// gates. A session is recorded ONLY when [usageConsent] is on (mirrored from
/// AppState.sharePerformance); a crash summary ONLY when [essentialConsent] is
/// on (AppState.shareEssential). Both default OFF. The default sink is the local
/// Debug-Log sink, so today "record" means "write to the log you pull" — nothing
/// leaves the device until a network sink is wired (Phase B).
class Analytics {
  Analytics(this.sink);
  final AnalyticsSink sink;

  bool usageConsent = false;
  bool essentialConsent = false;

  static Analytics instance = Analytics(LogAnalyticsSink());

  Future<void> recordSession(Map<String, dynamic> report) async {
    if (!usageConsent) return;
    await sink.sendSession(report);
  }

  Future<void> recordCrash(Map<String, dynamic> report) async {
    if (!essentialConsent) return;
    await sink.sendSession(report);
  }
}

/// Stable anonymous per-install id (uuid v4 in shared_preferences). Used to
/// group a user's sessions for later analysis without identifying them.
class AnonId {
  static const _key = 'anon_id';
  static String? _cached;

  static Future<String> get() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_key, id);
    }
    return _cached = id;
  }
}

/// FOR NOW: dumps the anonymous session report (from [buildSessionReport]) to
/// the Debug Log so we can see which surah/du'a was read, how far, and the slim
/// mistake list — the ground truth for tuning before any backend exists. The
/// report is deliberately slim: NO raw audio, NO audio sample ranges, and NO
/// per-phoneme scores ever reach it (see [buildSessionReport]/[slimMistake]).
class LogAnalyticsSink implements AnalyticsSink {
  @override
  Future<void> sendSession(Map<String, dynamic> report) async {
    final id = await AnonId.get();
    final payload = {'anonId': id, ...report};
    final label = report['kind'] == 'crash' ? 'CRASH' : 'SESSION';
    Log.d('analytics', '$label ${jsonEncode(payload)}');
  }
}

/// FOR LATER: posts the same report to Supabase's REST endpoint (anon key is
/// client-safe by design). Inert until [supabaseUrl]/[supabaseAnonKey] are
/// filled in — so it can ship disabled and be flipped on without code changes,
/// and no secret is committed. Provision the table with `supabase/sessions.sql`.
class SupabaseAnalyticsSink implements AnalyticsSink {
  // Leave empty to keep disabled. Fill from your Supabase project settings.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  @override
  Future<void> sendSession(Map<String, dynamic> report) async {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      Log.d('analytics', 'supabase disabled (no url/key) — session not uploaded');
      return;
    }
    try {
      final id = await AnonId.get();
      final res = await http.post(
        Uri.parse('$supabaseUrl/rest/v1/sessions'),
        headers: {
          'Content-Type': 'application/json',
          'apikey': supabaseAnonKey,
          'Authorization': 'Bearer $supabaseAnonKey',
          'Prefer': 'return=minimal',
        },
        body: jsonEncode({'anon_id': id, 'report': report}),
      );
      Log.d('analytics', 'supabase upload -> ${res.statusCode}');
    } catch (e, st) {
      Log.e('analytics', e, st);
    }
  }
}
