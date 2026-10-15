import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Supabase se usa junto a Firebase: Storage y Edge Functions. No tiene login
/// propio: cada petición lleva el ID token de Firebase del usuario
/// (Supabase → Third-party Auth → Firebase `mascoti-b27cf`).
abstract final class SupabaseBootstrap {
  static Future<void> initialize() async {
    if (!Env.hasSupabase) return; // la app abre igual; el registro avisará
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
      accessToken: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
    );
  }
}
