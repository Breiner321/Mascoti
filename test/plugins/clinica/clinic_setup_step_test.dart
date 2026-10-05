import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/router/pending_step_provider.dart';
import 'package:mascoti/plugins/clinica/clinica_plugin.dart';
import 'package:mascoti/plugins/clinica/clinica_routes.dart';
import 'package:mascoti/plugins/clinica/data/clinic_repository.dart';
import 'package:mascoti/plugins/clinica/presentation/clinic_providers.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  const clinicUser = AppUser(
    uid: 'vet',
    email: 'vet@correo.co',
    displayName: 'Vet',
    role: UserRole.clinica,
    clinicId: 'c1',
  );

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await firestore.doc('clinics/c1').set({'ownerUid': 'vet', 'estado': 'incompleto'});
  });

  ProviderContainer container({AppUser? user = clinicUser}) {
    final c = ProviderContainer(
      overrides: [
        clinicRepositoryProvider
            .overrideWithValue(ClinicRepository(firestore: firestore)),
        currentUserProvider.overrideWithValue(user),
        pluginRegistryProvider
            .overrideWithValue(PluginRegistry([const ClinicaPlugin()])),
      ],
    );
    addTearDown(c.dispose);
    c.listen(pendingStepProvider, (_, __) {});
    return c;
  }

  test('clínica incompleta → debe ir a su perfil de atención', () async {
    final c = container();
    expect(c.read(pendingStepProvider).isLoading, isTrue);

    await pumpEventQueue();
    expect(c.read(pendingStepProvider).value, ClinicaRoutes.setup);
  });

  test('al pasar a activo deja de ser obligatorio (RF-04)', () async {
    final c = container();
    await pumpEventQueue();

    await firestore.doc('clinics/c1').update({'estado': 'activo'});
    await pumpEventQueue();
    expect(c.read(pendingStepProvider).value, isNull);
  });

  test('un usuario sin clinicId no tiene paso pendiente', () async {
    const noClinic = AppUser(
      uid: 'x',
      email: 'x@correo.co',
      displayName: 'X',
      role: UserRole.clinica,
    );
    expect(const ClinicaPlugin().requiredStep(noClinic), isNull);

    final c = container(user: noClinic);
    await pumpEventQueue();
    expect(c.read(pendingStepProvider).value, isNull);
  });

  test('sin sesión no hay paso pendiente', () {
    final c = container(user: null);
    expect(c.read(pendingStepProvider).value, isNull);
  });
}
