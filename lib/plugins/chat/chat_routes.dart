/// Rutas del plugin chat. Otros plugins abren una conversación con
/// `context.push(ChatRoutes.conversation(chatId))` (escribiendo la ruta tal
/// cual, sin importar este archivo).
abstract final class ChatRoutes {
  static const inbox = '/chat';
  static const conversationPattern = '/chat/:chatId';

  /// Abre o crea la conversación y la muestra (no se queda en el historial
  /// de navegación). Clínica: `?ownerUid=…&ownerNombre=…&petId=…`;
  /// dueño: `?clinicId=…`.
  static const open = '/chat/abrir';

  static String conversation(String chatId) => '/chat/$chatId';

  static String openWithOwner({
    required String ownerUid,
    required String ownerNombre,
    required String petId,
  }) =>
      Uri(path: open, queryParameters: {
        'ownerUid': ownerUid,
        'ownerNombre': ownerNombre,
        'petId': petId,
      }).toString();
}
