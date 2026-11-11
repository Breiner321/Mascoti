import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/auth/domain/app_user.dart';
import '../../core/data/chat_providers.dart';
import '../../core/kernel/mascoti_plugin.dart';
import '../../core/router/navigator_keys.dart';
import 'chat_routes.dart';
import 'presentation/clinica/clinic_inbox_page.dart';
import 'presentation/comun/conversation_page.dart';
import 'presentation/dueno/owner_inbox_page.dart';

/// Plugin compartido por ambos roles: chat entre dueño y clínica (RF-15) e
/// intercambio de archivos (RF-16). Datos en `core/data/chat_repository.dart`.
class ChatPlugin extends MascotiPlugin {
  const ChatPlugin();

  @override
  String get id => 'chat';

  @override
  Set<UserRole> get roles => const {UserRole.dueno, UserRole.clinica};

  @override
  List<RouteBase> routes() => [
        GoRoute(
          path: ChatRoutes.inbox,
          builder: (context, state) => Consumer(
            builder: (context, ref, _) => ref.watch(currentUserProvider)?.role == UserRole.clinica
                ? const ClinicInboxPage()
                : const OwnerInboxPage(),
          ),
        ),
        // La conversación se abre a pantalla completa, sin barra inferior.
        GoRoute(
          path: ChatRoutes.conversationPattern,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) =>
              ConversationPage(chatId: state.pathParameters['chatId']!),
        ),
      ];

  /// "Mensajes" va al final: después de "Citas" (30) para el dueño y de
  /// "Agenda" (20) para la clínica. El número es el total sin leer.
  @override
  List<PluginDestination> destinations(UserRole role) => [
        PluginDestination(
          label: 'Mensajes',
          icon: Icons.chat_bubble_outline,
          selectedIcon: Icons.chat_bubble,
          path: ChatRoutes.inbox,
          order: role == UserRole.dueno ? 40 : 30,
          badge: unreadMessagesCountProvider,
        ),
      ];
}
