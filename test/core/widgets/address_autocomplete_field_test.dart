import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/places/address_search_service.dart';
import 'package:mascoti/core/places/place_address.dart';
import 'package:mascoti/core/places/places_providers.dart';
import 'package:mascoti/core/widgets/address_autocomplete_field.dart';

import '../fakes/fake_address_search.dart';

void main() {
  late FakeAddressSearch places;
  late GlobalKey<FormState> formKey;
  PlaceAddress? selected;

  setUp(() {
    places = FakeAddressSearch();
    formKey = GlobalKey<FormState>();
    selected = null;
  });

  Future<void> pumpField(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [addressSearchServiceProvider.overrideWithValue(places)],
        child: MaterialApp(
          home: Scaffold(
            body: Form(
              key: formKey,
              child: AddressAutocompleteField(onChanged: (v) => selected = v),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(AddressAutocompleteField.debounce);
    await tester.pump();
  }

  bool validate() => formKey.currentState!.validate();

  testWidgets('escoger una sugerencia con coordenadas es válido', (tester) async {
    await pumpField(tester);
    await type(tester, 'Calle 100');

    expect(find.text('Calle 100 # 15-20'), findsOneWidget);
    await tester.tap(find.text('Calle 100 # 15-20'));
    await tester.pumpAndSettle();

    expect(selected?.lat, bogotaAddress.lat);
    expect(validate(), isTrue);
    expect(find.text(AddressAutocompleteField.invalidMessage), findsNothing);
  });

  testWidgets('texto libre sin escoger de la lista no es válido', (tester) async {
    await pumpField(tester);
    await type(tester, 'Mi casa');

    expect(validate(), isFalse);
    await tester.pump();
    expect(find.text(AddressAutocompleteField.invalidMessage), findsOneWidget);
  });

  testWidgets('un lugar sin coordenadas se marca en rojo de inmediato',
      (tester) async {
    places.resolved = null;
    await pumpField(tester);
    await type(tester, 'Calle 100');
    await tester.tap(find.text('Calle 100 # 15-20'));
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(find.text(AddressAutocompleteField.invalidMessage), findsOneWidget);
  });

  testWidgets('editar el texto invalida la dirección escogida', (tester) async {
    await pumpField(tester);
    await type(tester, 'Calle 100');
    await tester.tap(find.text('Calle 100 # 15-20'));
    await tester.pumpAndSettle();
    expect(selected, isNotNull);

    await tester.enterText(find.byType(TextField), 'Calle 100 # 15-2');
    await tester.pump();
    expect(selected, isNull);
    expect(validate(), isFalse);
  });

  testWidgets('sin resultados muestra el estado vacío', (tester) async {
    places.suggestions = const [];
    await pumpField(tester);
    await type(tester, 'zzzz');
    expect(find.textContaining('No encontramos esa dirección'), findsOneWidget);
  });

  testWidgets('error de red muestra Reintentar y vuelve a buscar',
      (tester) async {
    places.error = Exception('sin red');
    await pumpField(tester);
    await type(tester, 'Calle 100');

    expect(find.textContaining('Verifica tu conexión'), findsOneWidget);
    places.error = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(find.text('Calle 100 # 15-20'), findsOneWidget);
    expect(places.queries, ['Calle 100', 'Calle 100']);
  });

  testWidgets('sin API key avisa que el buscador no está disponible',
      (tester) async {
    places.error = const AddressSearchUnavailable();
    await pumpField(tester);
    await type(tester, 'Calle 100');
    expect(find.textContaining('no está disponible'), findsOneWidget);
  });

  testWidgets('no busca con menos de 3 caracteres', (tester) async {
    await pumpField(tester);
    await type(tester, 'Ca');
    expect(places.queries, isEmpty);
  });
}
