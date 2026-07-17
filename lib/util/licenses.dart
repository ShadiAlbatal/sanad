import 'package:flutter/foundation.dart';

/// Registers attribution/notice text for the bundled non-pub components so they
/// appear in the in-app license page (`showLicensePage`). Flutter already
/// auto-aggregates the pub package licenses (sherpa_onnx Apache-2.0, http,
/// provider, etc.); these are the ones it can't see: the ASR model, the Qur'an
/// font, and the Qur'an text/layout data.
///
/// TODO(release): replace the bracketed placeholders with the EXACT upstream
/// license/EULA text before publishing — the model's terms and the KFGQPC font
/// EULA must travel verbatim with the app.
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Sanad — bundled data & model'],
      'Sanad bundles the following third-party components. Their terms apply to '
      'this app in addition to the app\'s own license.\n\n'
      'ASR model — "zipformer_p-quran" (Hugging Face: Muno459/zipformer_p-quran).\n'
      'Streaming zipformer2-ctc phoneme model used for recitation follow-along.\n'
      'License: free for NON-COMMERCIAL use ("for the sake of Allah") — no selling, '
      'subscriptions, paywalls, ads, or revenue — and these terms must be passed on '
      'to recipients.\n'
      '[TODO(release): paste the model\'s exact license text and confirm '
      'redistribution-in-app is permitted with the author.]\n\n'
      'Qur\'an font — KFGQPC "UthmanicHafs" (via QUL / quran.com).\n'
      'Used to render the mushaf. Redistributed under the KFGQPC font EULA.\n'
      '[TODO(release): paste the exact KFGQPC/QUL font EULA and record the font '
      'version, e.g. "UthmanicHafs1 VerNN".]\n\n'
      'Qur\'an text, tajwīd markup & page layout — quran.com API v4 / QUL and the '
      'zonetecde/mushaf-layout dataset.\n'
      'The 604-page mushaf layout, per-word Uthmani text and tajwīd colouring are '
      'derived from these sources.\n'
      '[TODO(release): record the exact upstream versions/commits and confirm the '
      'quran.com/QUL data terms permit redistribution with attribution.]\n\n'
      'ONNX Runtime (bundled by sherpa_onnx) — Apache License 2.0, © Microsoft.\n\n'
      'See THIRD_PARTY_NOTICES.md in the repository for the full list.',
    );
  });
}
