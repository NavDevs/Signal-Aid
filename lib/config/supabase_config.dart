/// Supabase project credentials.
///
/// IMPORTANT: Fill in YOUR values from the Supabase dashboard:
///   Project Settings → API → Project URL  →  paste as [url]
///   Project Settings → API → anon/public  →  paste as [anonKey]
///
/// Both Signal-Aid and Roadly share the SAME Supabase project,
/// so use the same values in both apps.
class SupabaseConfig {
  static const String url = 'YOUR_SUPABASE_URL';
  static const String anonKey = 'YOUR_SUPABASE_ANON_KEY';
}
