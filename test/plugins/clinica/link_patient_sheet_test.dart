import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/plugins/clinica/data/patients_repository.dart';
import 'package:mascoti/plugins/clinica/data/pet_link_api.dart';
import 'package:mascoti/plugins/clinica/presentation/clinic_providers.dart';
import 'package:mascoti/plugins/clinica/presentation/link_patient_sheet.dart';

/// Responde con [result] o lanza [failure]; registra los códigos enviados.
class _FakeLinkApi extends PetLinkApi {
  _FakeLinkApi({this.result, this.failure}) : super(null);

  final LinkedPet? result;
  final PetLinkFailure? failure;
  final codes = <String>[];

  @override
  Future<LinkedPet> link(String code) async {
    codes.add(code);
    if (failure != null) throw failure!;
    return result!;
  }
}

void main() {
  late FakeFirebaseFirestore firestore;

  const clinicUser = AppUser(
    uid: 'vet',
    email: 'vet@correo.co',
    displayName: 'Vet',
    role: UserRole.clinica,
    clinicId: 'c1',
  );

  const luna = LinkedPet(
    petId: 'p1',
    codigoPaciente: 'MSC-7K4P',
    nombre: 'Luna',
    especie: 'gato',
    duenoNombre: 'Ana Pérez',
    nueva: true,
  );

  setUp(() => firestore = FakeFirebaseFirestore());

  /// Pantalla con un botón que abre la hoja; muestra el petId que devuelve.
  Future<void> pumpSheet(WidgetTester tester, _FakeLinkApi api) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(clinicUser),
          petLinkApiProvider.overrideWithValue(api),
          patientsRepositoryProvider.overrideWithValue(PatientsRepository(firestore: firestore)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                String? result;
                return StatefulBuilder(
                  builder: (context, setState) => Column(
                    children: [
                      TextButton(
                        onPressed: () async {
                          final petId = await showLinkPatientSheet(context);
                          setState(() => result = petId);
                        },
                        child: const Text('Abrir'),
                      ),
                      Text('resultado: ${result ?? '-'}'),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester, String code) async {
    await tester.enterText(find.byType(TextField), code);
    await tester.tap(find.widgetWithText(FilledButton, 'Vincular'));
    await tester.pumpAndSettle();
  }

  testWidgets('vincula con el código, muestra la mascota y guarda el dueño', (tester) async {
    final api = _FakeLinkApi(result: luna);
    await pumpSheet(tester, api);

    await submit(tester, 'msc 7k4p');

    // El código se normaliza antes de enviarlo.
    expect(api.codes, ['MSC-7K4P']);
    expect(find.text('Paciente vinculado'), findsOneWidget);
    expect(find.text('Luna'), findsOneWidget);
    expect(find.text('Gato'), findsOneWidget);
    expect(find.text('Dueño: Ana Pérez'), findsOneWidget);
    final saved = await firestore.doc('clinics/c1/pacientes/p1').get();
    expect(saved.data()!['duenoNombre'], 'Ana Pérez');

    await tester.tap(find.text('Ver perfil'));
    await tester.pumpAndSettle();
    expect(find.text('resultado: p1'), findsOneWidget);
  });

  testWidgets('avisa si la mascota ya estaba vinculada', (tester) async {
    await pumpSheet(
      tester,
      _FakeLinkApi(
        result: const LinkedPet(
          petId: 'p1',
          codigoPaciente: 'MSC-7K4P',
          nombre: 'Luna',
          especie: 'gato',
          duenoNombre: '',
          nueva: false,
        ),
      ),
    );
    await submit(tester, 'MSC-7K4P');

    expect(find.text('Este paciente ya estaba vinculado'), findsOneWidget);
  });

  testWidgets('un código mal escrito no llama al servidor', (tester) async {
    final api = _FakeLinkApi(result: luna);
    await pumpSheet(tester, api);

    await submit(tester, 'MSC-12');

    expect(api.codes, isEmpty);
    expect(find.text('El código debe tener el formato MSC-XXXX.'), findsOneWidget);
  });

  testWidgets('código inexistente: mensaje claro y se puede corregir', (tester) async {
    await pumpSheet(
      tester,
      _FakeLinkApi(
        failure: const PetLinkFailure(
          PetLinkFailureKind.notFound,
          serverMessage: 'No existe una mascota con ese código.',
        ),
      ),
    );
    await submit(tester, 'MSC-7K4P');

    expect(find.text('No existe una mascota con ese código.'), findsOneWidget);
    expect(find.text('Paciente vinculado'), findsNothing);
    // Al escribir de nuevo el error desaparece.
    await tester.enterText(find.byType(TextField), 'MSC-7K4');
    await tester.pump();
    expect(find.text('No existe una mascota con ese código.'), findsNothing);
  });

  testWidgets('demasiados intentos: muestra cuándo volver a intentar', (tester) async {
    await pumpSheet(
      tester,
      _FakeLinkApi(
        failure: const PetLinkFailure(
          PetLinkFailureKind.tooManyAttempts,
          serverMessage: 'Demasiados intentos. Intenta de nuevo en 12 minutos.',
        ),
      ),
    );
    await submit(tester, 'MSC-7K4P');

    expect(find.text('Demasiados intentos. Intenta de nuevo en 12 minutos.'), findsOneWidget);
  });
}
