/*
 * Copy this file to supabase-config.js (which is ignored by Git) and replace
 * the placeholders. The anon key is designed for browser use; security comes
 * from RLS and RPC checks. Never put a service-role key here.
 */
window.PLANER_SUPABASE = {
  url: 'https://YOUR_PROJECT_REF.supabase.co',
  anonKey: 'YOUR_PUBLIC_ANON_KEY',
  // Public VAPID key for Web Push. This is safe to ship; never add its private key here.
  pushVapidPublicKey: 'YOUR_VAPID_PUBLIC_KEY',
  redirectTo: 'https://YOUR_GITHUB_USERNAME.github.io/YOUR_REPOSITORY/',
};
