# Pacta

Pacta is a mobile-first, cross-platform self-regulation app built with Flutter,
Riverpod, Drift, and Supabase.

## Local development

Install dependencies and run the test suite:

```powershell
flutter pub get
flutter test
```

To connect the App to a Supabase project, apply the migrations in
`supabase/migrations` and provide the project URL and publishable key at build
time:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

Without those values, the App remains runnable but sign-in reports that
Supabase has not been configured. Never provide a secret or service-role key to
the Flutter client.

Pacta registration is invitation-only. Before exposing a Supabase project,
open **Authentication > Providers > Email** in its dashboard and disable
**Allow new users to sign up**. Create or invite approved users through a
trusted administrative path; the client intentionally has no sign-up flow.
Keep this setting aligned in every deployed Supabase project.

The RLS boundary has pgTAP coverage in `supabase/tests/database`. With a local
Supabase stack running, install the project-pinned CLI and execute it with:

```powershell
pnpm install
pnpm exec supabase start
pnpm exec supabase test db
```

The Drift web worker and SQLite WebAssembly assets in `web/` match the locked
Drift release and are required for the offline cache on Flutter Web.
