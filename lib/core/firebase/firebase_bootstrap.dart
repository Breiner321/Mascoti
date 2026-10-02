import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

// Generado por `flutterfire configure` (ver docs/configuracion-inicial.md).
import '../../firebase_options.dart';
import '../config/env.dart';

abstract final class FirebaseBootstrap {
  static Future<void> initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (Env.useEmulators) {
      const host = Env.emulatorHost;
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      FirebaseFunctions.instanceFor(region: Env.functionsRegion)
          .useFunctionsEmulator(host, 5001);
      // Semana 3: agregar FirebaseStorage.instance.useStorageEmulator(host, 9199);
    }

    await GoogleSignIn.instance.initialize(
      serverClientId:
          Env.googleServerClientId.isEmpty ? null : Env.googleServerClientId,
    );
  }
}
