# TilawaAi — Analytics & Accounts plan (2026-07-16)

**Status (updated 2026-07-16 pm): Phase A is BUILT and local-only. Phases B & C are NOT built.**
- ✅ **Phase A** — `buildSessionReport` (pure, from the current pipeline), `Analytics` opt-in gate
  (`usageConsent`, default OFF), wired at Stop in the Quran + du'a states, local `LogAnalyticsSink`
  (writes to the Debug Log — nothing uploaded), and a "Data & Privacy" screen. Tests pin the report
  shape, the no-audio/no-PII guarantee, and the gate. Nothing leaves the device.
- ⬜ **Phase B** — offline queue + Supabase upload. Needs YOU to create the project, run the schema
  below, and inject creds via `--dart-define` (below). A privacy policy must land before this ships.
- ⬜ **Phase C** — accounts (magic-link / Google / guest).

Original planning notes follow (the "nothing is implemented" framing below is now historical — Phase A
above is done). The two Settings toggles are now wired: `sharePerformance` gates recording.

## Principles (non-negotiable)
- **Opt-in.** Nothing is sent unless the user turns on the toggle. Default OFF.
- **Anonymous.** A random per-install UUID (`AnonId`, already in `analytics.dart`) — no name,
  email, account, contacts, or location. **Works WITHOUT accounts** (see Q&A).
- **Never the audio.** Raw mic PCM is never uploaded. (Phoneme text / accuracy may be, per below.)
- **Offline-first.** The app works fully offline; reports queue on-device and upload later when online.
- **Transparent.** A "Data & Privacy" screen lists EXACTLY what is and isn't sent. A privacy policy
  is required before a real release that uploads anything.

## The two questions answered
**Q: If data stays LOCAL, how does it reach me to improve the app?**
It doesn't reach you automatically. A local sink only writes the report to the Debug Log on THAT
device — you only see it when YOU pull that device's logs (your own testing). It does **not** gather
from other users. So: local sink = great for your own tuning now; to collect from real users you need
the upload (Supabase). Recommended path: build the report + local sink first (safe, immediate value),
then add the queued Supabase upload when you're ready.

**Q: Can data be collected WITHOUT accounts?**
Yes. `AnonId` is a random UUID stored in `shared_preferences` per install; it groups a device's
sessions for analysis without any login. Accounts are a SEPARATE, optional track — anonymous analytics
does not need them.

## What would be SENT vs NOT (draft — show this verbatim to the user)
SENT (only if opted in, anonymous):
- a random install id (not tied to you)
- per session: which surah / dua, how far you reached, how many phonemes the model decoded,
  whether it locked on (anchored), the tajwīd flags it raised (ref→heard letters), skipped count,
  session length, app version + coarse device model + OS.
NOT sent, ever:
- your voice / audio recording, your name/email/account, contacts, location, anything that identifies you.

(Decision to make: is the "what the model heard" phoneme text OK to send? It's content-ish but not audio
and helps tuning. Recommend YES but call it out explicitly in the privacy screen.)

## Architecture (build order)
1. **Report builder** — build a session report from the CURRENT pipeline at Stop (the old
   `SessionRecorder.report()` was tied to the DELETED per-token engine — rebuild it). Fields ≈
   `{schemaVersion, kind:'quran'|'dua', surah|duaId, reached, tokens, anchored, mistakes:[{loc,ref,heard,kind}],
   skipped, durationMs, app, platform, device}`. Keep it a `Map<String,dynamic>` → JSONB.
2. **Consent gate** — only build/queue if `sharePerformance` (usage) / `shareEssential` (crash-safety) is ON.
   Wire the toggles (today they store a bool wired to nothing).
3. **Local sink NOW** — `LogAnalyticsSink` already dumps the report to the Debug Log. Wire it at Stop
   (gated). Zero network. Gives you tuning data via the logs you already pull.
4. **Offline queue** — persist pending reports (a JSON list in a file / prefs). Flush on next launch and/or
   on connectivity regained (`connectivity_plus`). Drop-oldest cap so it can't grow unbounded.
5. **Supabase upload** — `SupabaseAnalyticsSink` already POSTs to `/rest/v1/sessions`. Flip on by setting
   creds (below). It reads from the same queue; on success removes from queue, on failure keeps for retry.
6. **Transparency UI** — a "Data & Privacy" screen (linked from Settings) with the SENT/NOT-SENT list +
   a link to the privacy policy. The toggle labels stay clear.

## Supabase setup — EXACT steps (you do this; app stays offline-capable)
1. Create a Supabase project (free tier fine). Note the **Project URL** and the **anon public key**
   (Settings → API). The anon key is client-safe by design (RLS restricts what it can do).
2. In the SQL editor, run the schema below (updated for the CURRENT pipeline — supersedes the old
   `supabase/sessions.sql`, whose generated columns reference deleted per-token fields).
3. Build the app with the creds injected (NOT committed):
   `flutter build apk --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...`
   (or put them in a `--dart-define-from-file=env.json` that is gitignored).
4. Verify: recite a session with the toggle ON + online → a row appears in `public.sessions`. Offline →
   it queues and uploads on next online launch. Toggle OFF → nothing queued or sent.

### Proposed schema (run this; replaces the old generated columns)
```sql
create table if not exists public.sessions (
  id           bigint generated always as identity primary key,
  anon_id      text        not null,
  created_at   timestamptz not null default now(),
  -- cheap top-level columns for dashboards (match the CURRENT report)
  kind         text    generated always as (report->>'kind')      stored,  -- 'quran' | 'dua'
  surah        int     generated always as ((report->>'surah')::int)     stored,
  reached      int     generated always as ((report->>'reached')::int)   stored,
  tokens       int     generated always as ((report->>'tokens')::int)    stored,
  anchored     boolean generated always as ((report->>'anchored')::boolean) stored,
  mistake_count int    generated always as ((report->>'mistakeCount')::int) stored,
  skipped      int     generated always as ((report->>'skipped')::int)   stored,
  app_version  text    generated always as (report->>'app')       stored,
  report       jsonb   not null
);
create index if not exists sessions_anon_idx    on public.sessions (anon_id);
create index if not exists sessions_created_idx  on public.sessions (created_at);
alter table public.sessions enable row level security;
-- anon may INSERT its own rows, never SELECT others'
create policy "anon insert" on public.sessions for insert to anon with check (true);
```
(If a generated column's field is missing from a report, make it nullable / drop that column — keep the
`report` JSONB as the source of truth so the schema can evolve without migrations.)

## Accounts (separate, optional track — NOT needed for analytics)
- Use **Supabase Auth**: **magic link (email OTP)** + **Google OAuth**, plus **continue as guest**.
- Guest = the current default; the app must stay fully usable with no login.
- Anonymous analytics keeps using `AnonId` regardless of login. IF a user later signs in, you *could*
  attach their user id to future rows (opt-in) — but keep anonymous the default.
- Needs: `supabase_flutter` package, provider config (redirect URLs for magic link / Google), a Profile
  screen wired to real auth (the current `UserScreen` is a Guest placeholder). This is a real feature —
  plan it as its own phase after analytics.

## Recommended rollout
Phase A (safe, local): report builder + consent gate + local Log sink + Data&Privacy screen.
Phase B: offline queue + Supabase upload (you provision project + run schema + provide creds).
Phase C: accounts (magic link / Google / guest) — optional, later.
Privacy policy must land before Phase B ships to real users.
