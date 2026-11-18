import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/auth_providers.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/data/chat_providers.dart';
import 'package:mascoti/core/domain/chat.dart';
import 'package:mascoti/core/domain/chat_message.dart';
import 'package:mascoti/core/kernel/plugin_manifest.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/router/navigator_keys.dart';
import 'package:mascoti/plugins/chat/chat_plugin.dart';

const owner = AppUser(uid: 'ana', email: 'ana@example.com', displayName: 'Ana', role: UserRole.dueno);

Chat chat(String id, {int unreadAna = 0, String? last}) => Chat(
      id: id,
      ownerUid: 'ana',
      clinicId: id.split('_').last,
      clinicOwnerUid: 'vet_${id.split('_').last}',
      ownerNombre: 'Ana',
      clinicNombre: 'Clínica ${id.split('_').last}',
      noLeidos: {'ana': unreadAna},
      lastMessage: last == null
          ? null
          : ChatLastMessage(texto: last, tipo: ChatMessageType.texto, senderUid: 'vet'),
    );

void main() {
  group('ChatPlugin', () {
    const plugin = ChatPlugin();

    test('pestaña "Mensajes" para ambos roles, al final y con contador', () {
      final owner = plugin.destinations(UserRole.dueno).single;
      final clinic = plugin.destinations(UserRole.clinica).single;
      expect(owner.label, 'Mensajes');
      expect(owner.path, '/chat');
      expect(owner.order, 40);
      expect(clinic.order, 30);
      expect(owner.badge, same(unreadMessagesCountProvider));
    });

    test('la conversación se abre a pantalla completa', () {
      final routes = plugin.routes().cast<GoRoute>();
      expect(routes.map((r) => r.path), ['/chat', '/chat/abrir', '/chat/:chatId']);
      expect(routes[1].parentNavigatorKey, same(rootNavigatorKey));
      expect(routes.last.parentNavigatorKey, same(rootNavigatorKey));
    });

    test('está registrado en el manifiesto y las rutas no chocan', () {
      final registry = PluginRegistry(enabledPlugins);
      expect(registry.isEnabled('chat'), isTrue);
      expect(registry.hasRoute('/chat/ana_c1'), isTrue);
      expect(registry.destinationsFor(UserRole.clinica).map((d) => d.label), contains('Mensajes'));
    });
  });

  test('el contador suma los no leídos del usuario en todas sus conversaciones', () async {
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWithValue(owner),
      userChatsProvider.overrideWith((ref, uid) => Stream.value([
            chat('ana_c1', unreadAna: 2),
            chat('ana_c2', unreadAna: 3),
            chat('ana_c3'),
          ])),
    ]);
    addTearDown(container.dispose);
    final sub = container.listen(unreadMessagesCountProvider, (_, __) {});
    addTearDown(sub.close);
    await container.read(userChatsProvider('ana').future);
    expect(container.read(unreadMessagesCountProvider), 5);
  });
}
