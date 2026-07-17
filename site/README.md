# Sanad site (`sanad.ylensolutions.com`)

Static marketing + legal pages for Sanad. No build step, no framework — hand-written
HTML/CSS/JS, self-contained (inline CSS, tiny inline JS for the language switch). Same
pattern as SnapNote (`chatnotes/site/`) and Agenda (`agenda-v2/site/`): **one repo, one
Cloudflare project per app.**

```
site/
├─ wrangler.toml            name = "sanad-site", assets from public/
├─ README.md
└─ public/                  ← served root
   ├─ index.html            landing — English (canonical)
   ├─ ar/index.html         landing — Arabic (RTL, IBM Plex Sans Arabic + Amiri)
   ├─ privacy.html          privacy policy (trilingual EN/AR/SV, inline JS switch)
   ├─ delete-account.html   data-deletion (trilingual EN/AR/SV, inline JS switch)
   ├─ favicon.svg
   ├─ _headers              security headers
   └─ _redirects            SPA fallback only
```

## Domains — site vs. app

Two distinct hosts; do not confuse them:

- **`sanad.ylensolutions.com`** — this marketing site (its own canonical/meta domain).
- **`app.sanad.ylensolutions.com`** — the actual Sanad app (separate deploy). Every
  "Open the app" / CTA / web-app link on the site points here, **not** at the marketing domain.

Pre-launch note: the Android app is "Coming soon to Google Play" (custom inline badge, no
fake store link yet). The "Open the app" links already point at the `app.` subdomain so they
work the moment the web app is live — add the real Play Store URL to the badges when the
listing goes public.

## Deploy — Cloudflare Pages (or Wrangler)

Its own Pages project, **separate from the app** (`app.sanad.ylensolutions.com`) and from the
company site (`ylensolutions.com`).

- **Wrangler:** from this `site/` directory, run `wrangler deploy`. (`wrangler.toml` sets
  `name = "sanad-site"` and serves assets from `public/`.)
- **Pages dashboard:** connect this repo and set the project **root directory to `site/`**
  (assets served from `public/`).
- Custom domain: `sanad.ylensolutions.com`.
- No worker / no `www` needed — `index.html` is the landing, so `/` just works.

Canonical legal URLs (hard-linked from the mobile app): `sanad.ylensolutions.com/privacy`
and `sanad.ylensolutions.com/delete-account`.

### Redirect-loop gotcha

Clean URLs (`/privacy`, `/delete-account`, `/ar/`) are automatic on Cloudflare Pages.
**Do NOT** add explicit `/privacy /privacy.html 200` rewrites to `_redirects`: they collide
with Pages' built-in `.html` → clean-URL canonicalization and cause an infinite redirect loop.
`_redirects` therefore contains only the SPA fallback (`/* /index.html 200`).

## Languages (EN / AR)

Two mechanisms, each where it fits — the SnapNote / Agenda pattern:

- **Landing** — separate static files per language (`/`, `/ar/`) with `hreflang` + `canonical`
  tags and a real-link switcher. Each language is its own crawlable URL so Google indexes and
  serves the right one. Arabic is RTL with IBM Plex Sans Arabic (UI) + Amiri (headings/Qur'an).
  Swedish landing was left out of scope; the legal pages still cover SV.
- **Legal pages** — one URL each, trilingual (EN/AR/SV) via a self-contained client-side switch
  (English inline in the HTML, AR + SV in a JS dict; RTL for Arabic; choice persisted to
  `localStorage` under `sanad_lang`). SEO doesn't matter for a policy, and one canonical URL is
  what the mobile app hard-links to.

## Things to fill in before / at launch

- Real support email — currently `support@ylensolutions.com` (footer Contact) and
  `privacy@ylensolutions.com` (legal pages). Swap if different.
- Google Play listing URL — add to the "Coming soon to Google Play" badges once live.
- Confirm the web app is reachable at `app.sanad.ylensolutions.com` before publishing the CTAs.
