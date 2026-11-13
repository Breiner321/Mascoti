import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/chat_providers.dart';
import 'package:mascoti/core/data/chat_repository.dart';
import 'package:mascoti/core/domain/chat.dart';
import 'package:mascoti/core/domain/chat_message.dart';
import 'package:mascoti/core/domain/pet.dart';
import 'package:mascoti/core/theme/app_theme.dart';
import 'package:mascoti/plugins/chat/data/chat_lookup_repository.dart';
import 'package:mascoti/plugins/chat/presentation/clinica/clinic_inbox_filter.dart';
import 'package:mascoti/plugins/chat/presentation/clinica/clinic_inbox_page.dart';
import 'package:mascoti/plugins/chat/presentation/comun/chat_ui_providers.dart';

const clinicUser = AppUser(
  uid: 'vet',
  email: 'vet@correo.co',
  displayName: 'Vet Sur',
  role: UserRole.clinica,
  clinicId: 'c1',
);

final now = DateTime.utc(2026, 11, 12, 15);

Chat chat(String owner, String nombre, {int unread = 0, String? last, int minutesAgo = 0}) => Chat(
      id: '${owner}_c1',
      ownerUid: owner,
      clinicId: 'c1',
      clinicOwnerUid: 'vet',
      ownerNombre: nombre,
      clinicNombre: 'Vet Sur',
      noLeidos: {owner: 0, 'vet': unread},
      lastMessage: last == null
          ? null
          : ChatLastMessage(texto: last, tipo: ChatMessageType.texto, senderUid: owner),
      lastMessageAt: now.subtract(Duration(minutes: minutesAgo)),
    );

Pet pet(String id, String owner, String nombre) =>
    Pet(id: id, ownerUid: owner, nombre: nombre, especie: PetSpecies.perro);

void main() {
  group('buildClinicInbox', () {
    final chats = [
      chat('ana', 'Ana Pérez', unread: 2, last: '¿Cómo sigue?'),
      chat('beto', 'Beto Ruiz', last: 'Gracias'),
      chat('caro', 'Carolina Gómez', unread: 1),
    ];
    final pets = [pet('p1', 'ana', 'Toby'), pet('p2', 'beto', 'Ñoño'), pet('p3', 'ana', 'Luna')];

    List<String> owners({String query = '', bool unreadOnly = false}) => [
          for (final e in buildClinicInbox(
            chats: chats,
            linkedPets: pets,
            clinicUid: 'vet',
            query: query,
            unreadOnly: unreadOnly,
          ))
            e.chat.ownerNombre,
        ];

    test('mantiene el orden por fecha y agrega las mascotas de cada dueño', () {
      final entries = buildClinicInbox(chats: chats, linkedPets: pets, clinicUid: 'vet');
      expect(entries.map((e) => e.chat.ownerNombre), ['Ana Pérez', 'Beto Ruiz', 'Carolina Gómez']);
      expect(entries.first.pets.map((p) => p.nombre), ['Luna', 'Toby']);
      expect(entries.last.pets, isEmpty);
    });

    test('busca por dueño o mascota sin tildes ni mayúsculas', () {
      expect(owners(query: 'perez'), ['Ana Pérez']);
      expect(owners(query: 'LUNA'), ['Ana Pérez']);
      expect(owners(query: 'nono'), ['Beto Ruiz']);
      expect(owners(query: 'xyz'), isEmpty);
    });

    test('"Sin leer" deja solo las conversaciones con mensajes sin leer', () {
      expect(owners(unreadOnly: true), ['Ana Pérez', 'Carolina Gómez']);
      expect(owners(unreadOnly: true, query: 'toby'), ['Ana Pérez']);
    });
  });

  group('ClinicInboxPage', () {
    late FakeFirebaseFirestore firestore;

    setUp(() => firestore = FakeFirebaseFirestore());

    Future<void> addChat(Chat c) => firestore.doc('chats/${c.id}').set({
          ...c.toCreateMap(),
          'lastMessage': c.lastMessage?.toMap(),
          'lastMessageAt': Timestamp.fromDate(c.lastMessageAt!),
          'noLeidos': c.noLeidos,
          'createdAt': Timestamp.fromDate(c.lastMessageAt!),
        });

    Future<void> addPet(Pet p) => firestore.doc('pets/${p.id}').set({
          'ownerUid': p.ownerUid,
          'nombre': p.nombre,
          'especie': 'perro',
          'clinicasAutorizadas': ['c1'],
        });

    Future<void> pumpPage(WidgetTester tester, {Stream<List<Chat>>? chats}) async {
      final stream = chats;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(clinicUser),
          chatRepositoryProvider.overrideWithValue(ChatRepository(firestore: firestore)),
          chatLookupRepositoryProvider
              .overrideWithValue(ChatLookupRepository(firestore: firestore)),
          inboxClockProvider.overrideWithValue(() => now),
          if (stream != null) userChatsProvider.overrideWith((ref, uid) => stream),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: ClinicInboxPage())),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('lista las conversaciones más recientes primero con mascotas y no leídos',
        (tester) async {
      await addChat(chat('beto', 'Beto Ruiz', last: 'Gracias', minutesAgo: 90));
      await addChat(chat('ana', 'Ana Pérez', unread: 2, last: '¿Cómo sigue Toby?', minutesAgo: 5));
      await addPet(pet('p1', 'ana', 'Toby'));
      await pumpPage(tester);

      final ana = tester.getTopLeft(find.text('Ana Pérez'));
      final beto = tester.getTopLeft(find.text('Beto Ruiz'));
      expect(ana.dy, lessThan(beto.dy));
      expect(find.text('Toby'), findsOneWidget);
      expect(find.text('¿Cómo sigue Toby?'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Hace 5 min'), findsOneWidget);
      expect(find.text('Hace 1 h'), findsOneWidget);
      expect(find.text('AP'), findsOneWidget);
    });

    testWidgets('el filtro "Sin leer" y el buscador', (tester) async {
      await addChat(chat('ana', 'Ana Pérez', unread: 1, last: 'Hola', minutesAgo: 1));
      await addChat(chat('beto', 'Beto Ruiz', last: 'Gracias', minutesAgo: 2));
      await addPet(pet('p2', 'beto', 'Rocky'));
      await pumpPage(tester);

      await tester.tap(find.widgetWithText(FilterChip, 'Sin leer'));
      await tester.pumpAndSettle();
      expect(find.text('Ana Pérez'), findsOneWidget);
      expect(find.text('Beto Ruiz'), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'Sin leer'));
      await tester.enterText(find.byType(TextField), 'rocky');
      await tester.pumpAndSettle();
      expect(find.text('Beto Ruiz'), findsOneWidget);
      expect(find.text('Ana Pérez'), findsNothing);

      await tester.enterText(find.byType(TextField), 'nadie');
      await tester.pumpAndSettle();
      expect(find.text('No hay conversaciones que coincidan con la búsqueda.'), findsOneWidget);
    });

    testWidgets('"Sin leer" sin mensajes pendientes', (tester) async {
      await addChat(chat('beto', 'Beto Ruiz', last: 'Gracias'));
      await pumpPage(tester);
      await tester.tap(find.widgetWithText(FilterChip, 'Sin leer'));
      await tester.pumpAndSettle();
      expect(find.text('No tienes mensajes sin leer.'), findsOneWidget);
    });

    testWidgets('vacía y error con reintento', (tester) async {
      await pumpPage(tester);
      expect(find.text('Aún no tienes conversaciones con tus clientes.'), findsOneWidget);

      await tester.pumpWidget(Container());
      await pumpPage(tester, chats: Stream.error(Exception('sin red')));
      expect(find.text('No se pudieron cargar tus mensajes.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });
}
