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

The Drift web worker and SQLite WebAssembly assets in `web/` match the locked
Drift release and are required for the offline cache on Flutter Web.
