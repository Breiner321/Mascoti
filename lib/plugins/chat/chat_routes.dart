/// Rutas del plugin chat. Otros plugins abren una conversación con
/// `context.push(ChatRoutes.conversation(chatId))` (escribiendo la ruta tal
/// cual, sin importar este archivo).
abstract final class ChatRoutes {
  static const inbox = '/chat';
  static const conversationPattern = '/chat/:chatId';

  static String conversation(String chatId) => '/chat/$chatId';
}
