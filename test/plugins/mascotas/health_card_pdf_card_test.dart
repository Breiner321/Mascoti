import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/mascotas/data/health_card_repository.dart';
import 'package:mascoti/plugins/mascotas/presentation/health_card_providers.dart';
import 'package:mascoti/plugins/mascotas/presentation/pets_providers.dart';
import 'package:mascoti/plugins/mascotas/presentation/widgets/health_card_pdf_card.dart';

import '../../a11y.dart';

const luna = Pet(id: 'p1', ownerUid: 'ana', nombre: 'Luna', especie: PetSpecies.perro);

/// Repositorio con la Edge Function simulada.
class FakeHealthCardRepository extends HealthCardRepository {
  FakeHealthCardRepository(FakeFirebaseFirestore firestore) : super(firestore: firestore);

  final results = <Future<GeneratedHealthCard> Function()>[];
  final generated = <String>[];
  final downloads = <String>[];

  @override
  Future<GeneratedHealthCard> generate(String petId) {
    generated.add(petId);
    return results.removeAt(0)();
  }

  @override
  Future<Uint8List> download(String url) async {
    downloads.add(url);
    return Uint8List.fromList('%PDF-1.7'.codeUnits);
  }
}

GeneratedHealthCard card({int vacunas = 2, DateTime? at}) => GeneratedHealthCard(
      url: 'https://x.supabase.co/storage/v1/object/sign/documentos/carnet.pdf?token=t',
      path: 'pets/p1/documentos/carnet-2026-11-24.pdf',
      generadoEn: at ?? DateTime.now(),
      vacunas: vacunas,
    );

void main() {
  late FakeFirebaseFirestore firestore;
  late FakeHealthCardRepository repository;
  late List<Uri> opened;
  late List<(int, String)> shared;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FakeHealthCardRepository(firestore);
    opened = [];
    shared = [];
  });

  Future<void> pump(WidgetTester tester, {ThemeData? theme, bool settle = true}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        healthCardRepositoryProvider.overrideWithValue(repository),
        externalUrlOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
        healthCardSharerProvider.overrideWithValue((pdf, name) async {
          shared.add((pdf.length, name));
        }),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: const Scaffold(body: SingleChildScrollView(child: HealthCardPdfCard(pet: luna))),
      ),
    ));
    if (settle) await tester.pumpAndSettle();
  }

  testWidgets('inicio: título, botón y sin carnet previo', (tester) async {
    await pump(tester);
    expect(find.text('Carnet de vacunas'), findsOneWidget);
    expect(find.text('Generar carnet PDF'), findsOneWidget);
    expect(find.textContaining('Último carnet'), findsNothing);
  });

  testWidgets('muestra la fecha del último carnet generado', (tester) async {
    await firestore.doc('pets/p1/documentos/carnet').set({
      'path': 'pets/p1/documentos/carnet-2026-11-20.pdf',
      // 20/11/2026 a las 10 a. m. en Colombia.
      'generadoAt': Timestamp.fromDate(DateTime.utc(2026, 11, 20, 15)),
      'vacunas': 3,
    });
    await pump(tester);
    expect(find.textContaining('Último carnet:'), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);
  });

  testWidgets('cargando: indicador y texto mientras se genera', (tester) async {
    final pending = Completer<GeneratedHealthCard>();
    repository.results.add(() => pending.future);
    await pump(tester);

    await tester.tap(find.text('Generar carnet PDF'));
    await tester.pump();
    expect(find.text('Generando tu carnet…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Generar carnet PDF'), findsNothing);
    expect(repository.generated, ['p1']);

    pending.complete(card());
    await tester.pumpAndSettle();
  });

  testWidgets('listo: abre el PDF en el visor y lo comparte', (tester) async {
    final generatedCard = card();
    repository.results.add(() async => generatedCard);
    await pump(tester);

    await tester.tap(find.text('Generar carnet PDF'));
    await tester.pumpAndSettle();

    // Se abre solo al terminar.
    expect(opened, [Uri.parse(generatedCard.url)]);
    expect(find.text('Carnet listo · 2 vacunas'), findsOneWidget);
    expect(find.text('El enlace vence en 15 minutos.'), findsOneWidget);

    await tester.tap(find.text('Abrir PDF'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(2));

    await tester.tap(find.text('Compartir'));
    await tester.pumpAndSettle();
    expect(repository.downloads, [generatedCard.url]);
    expect(shared, [(8, healthCardFileName('Luna', generatedCard.generadoEn))]);
  });

  testWidgets('sin vacunas también se genera y lo dice', (tester) async {
    repository.results.add(() async => card(vacunas: 0));
    await pump(tester);
    await tester.tap(find.text('Generar carnet PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Carnet listo · sin vacunas registradas'), findsOneWidget);
  });

  testWidgets('error: mensaje y "Reintentar" vuelve a generar', (tester) async {
    repository.results
      ..add(() async => throw HealthCardFailure.network)
      ..add(() async => card());
    await pump(tester);

    await tester.tap(find.text('Generar carnet PDF'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudo conectar. Verifica tu conexión'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(opened, isEmpty);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(repository.generated, ['p1', 'p1']);
    expect(find.text('Carnet listo · 2 vacunas'), findsOneWidget);
    expect(opened, hasLength(1));
  });

  testWidgets('enlace vencido: "Abrir PDF" genera uno nuevo', (tester) async {
    repository.results
      ..add(() async => card(at: DateTime.now().subtract(const Duration(minutes: 20))))
      ..add(() async => card());
    await pump(tester);
    await tester.tap(find.text('Generar carnet PDF'));
    await tester.pumpAndSettle();
    expect(repository.generated, hasLength(2));
    expect(opened, hasLength(1));
  });

  test('nombre del archivo compartido', () {
    expect(healthCardFileName('Ñoño Pérez', DateTime.utc(2026, 11, 24, 3)), 'carnet_nono_perez_2026-11-23.pdf');
  });

  group('accesibilidad (Cambio 3)', () {
    testWidgets('áreas táctiles, etiquetas y contraste: inicio y listo', (tester) async {
      repository.results.add(() async => card());
      await pump(tester);
      await expectAccessible(tester);
      await tester.tap(find.text('Generar carnet PDF'));
      await tester.pumpAndSettle();
      await expectAccessible(tester);
    });

    testWidgets('texto al 200 % sin desbordes en listo y error', (tester) async {
      useLargeText(tester);
      repository.results
        ..add(() async => throw const HealthCardFailure('No pudimos generar el carnet. Intenta de nuevo.'))
        ..add(() async => card());
      await pump(tester);
      expectNoOverflow(tester);
      await tester.tap(find.text('Generar carnet PDF'));
      await tester.pumpAndSettle();
      expectNoOverflow(tester);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expectNoOverflow(tester);
      expect(find.text('Compartir'), findsOneWidget);
    });

    testWidgets('modo oscuro', (tester) async {
      AppColors.palette = AppPalette.dark;
      addTearDown(() => AppColors.palette = AppPalette.light);
      repository.results.add(() async => throw HealthCardFailure.generic);
      await pump(tester, theme: AppTheme.of(AppPalette.dark));
      await tester.tap(find.text('Generar carnet PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);
      await expectAccessible(tester);
    });
  });
}
