-- TilawaAi anonymous recitation-session analytics.
-- Anonymous only: `anon_id` is a random per-install uuid (no account / PII).
-- The full per-session report (verses read, what the model heard, per-word and
-- per-phoneme accuracy) is stored as JSONB so the schema can evolve without
-- migrations while we're still learning what to measure.
--
-- Enable later by filling SUPABASE_URL / SUPABASE_ANON_KEY (see
-- lib/services/analytics.dart) and running this in the Supabase SQL editor.

create table if not exists public.sessions (
  id           bigint generated always as identity primary key,
  anon_id      text not null,
  created_at   timestamptz not null default now(),
  -- denormalised top-level metrics for cheap querying/dashboards
  words_scored int  generated always as ((report->>'wordsScored')::int) stored,
  word_accuracy numeric generated always as ((report->>'wordAccuracy')::numeric) stored,
  avg_pron_prob numeric generated always as ((report->>'avgPronProb')::numeric) stored,
  major        int  generated always as ((report->>'major')::int) stored,
  skipped      int  generated always as ((report->>'skipped')::int) stored,
  off_text     int  generated always as ((report->>'offText')::int) stored,
  report       jsonb not null
);

create index if not exists sessions_anon_idx on public.sessions (anon_id);
create index if not exists sessions_created_idx on public.sessions (created_at);

-- Anonymous inserts only: the app may add its own sessions, never read others'.
alter table public.sessions enable row level security;

create policy "anon insert" on public.sessions
  for insert to anon
  with check (true);
