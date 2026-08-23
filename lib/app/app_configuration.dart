class AppConfiguration {
  const AppConfiguration({
    required this.supabaseUrl,
    required this.publishableKey,
  });

  const AppConfiguration.fromEnvironment()
    : supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
      publishableKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  final String supabaseUrl;
  final String publishableKey;

  bool get hasSupabase => supabaseUrl.isNotEmpty && publishableKey.isNotEmpty;
}
