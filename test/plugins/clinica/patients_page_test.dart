import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/plugins/clinica/data/patients_repository.dart';
import 'package:mascoti/plugins/clinica/presentation/clinic_providers.dart';
import 'package:mascoti/plugins/clinica/presentation/patient_tile.dart';
import 'package:mascoti/plugins/clinica/presentation/patients_page.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  const clinicUser = AppUser(
    uid: 'vet',
    email: 'vet@correo.co',
    displayName: 'Vet',
    role: UserRole.clinica,
    clinicId: 'c1',
  );

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(clinicUser),
          patientsRepositoryProvider.overrideWithValue(PatientsRepository(firestore: firestore)),
        ],
        child: const MaterialApp(home: Scaffold(body: PatientsPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> addPet(String id, String nombre, String especie, {List<String>? alergias}) =>
      firestore.doc('pets/$id').set({
        'ownerUid': 'ana',
        'nombre': nombre,
        'especie': especie,
        'alergias': alergias ?? <String>[],
        'clinicasAutorizadas': ['c1'],
      });

  testWidgets('sin pacientes: estado vacío que explica cómo vincular', (tester) async {
    await pumpPage(tester);

    expect(find.text('Aún no tienes pacientes vinculados'), findsOneWidget);
    expect(find.textContaining('código de paciente'), findsOneWidget);
    expect(find.text('Vincular paciente'), findsOneWidget);
  });

  testWidgets('lista las mascotas con su dueño y filtra con el buscador', (tester) async {
    await addPet('p1', 'Luna', 'gato', alergias: ['Penicilina']);
    await addPet('p2', 'Toby', 'perro');
    await firestore.doc('clinics/c1/pacientes/p1').set({'duenoNombre': 'Ana Pérez'});
    await pumpPage(tester);

    expect(find.byType(PatientTile), findsNWidgets(2));
    expect(find.text('Dueño: Ana Pérez'), findsOneWidget);
    expect(find.text('Dueño: sin registrar'), findsOneWidget);
    // Aviso de alergias en la fila.
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'perez');
    await tester.pump();
    expect(find.byType(PatientTile), findsOneWidget);
    expect(find.text('Luna'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'loro');
    await tester.pump();
    expect(find.byType(PatientTile), findsNothing);
    expect(find.text('Ningún paciente coincide con "loro"'), findsOneWidget);
  });
}
