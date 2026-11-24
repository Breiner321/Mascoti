/// Pide un enlace de lectura a `adjuntos-chat`.
typedef AttachmentUrlFetcher = Future<String> Function({
  required String chatId,
  required String path,
});

/// Enlaces de lectura de los adjuntos del chat (RF-16). `adjuntos-chat` los
/// entrega por 15 min; aquí se reutilizan hasta [maxAge] y después se pide
/// uno nuevo sin que el usuario lo note. [url] con `refresh: true` fuerza uno
/// nuevo (la imagen no cargó con el anterior).
class AttachmentLinkCache {
  AttachmentLinkCache(this._fetch, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// Un poco menos que los 15 min del servidor, para no usar uno a punto de
  /// vencer.
  static const maxAge = Duration(minutes: 13);

  final AttachmentUrlFetcher _fetch;
  final DateTime Function() _clock;
  final _links = <String, ({String url, DateTime at})>{};
  final _inFlight = <String, Future<String>>{};

  Future<String> url({required String chatId, required String path, bool refresh = false}) {
    final cached = _links[path];
    if (!refresh && cached != null && _clock().difference(cached.at) < maxAge) {
      return Future.value(cached.url);
    }
    return _inFlight[path] ??= () async {
      try {
        final url = await _fetch(chatId: chatId, path: path);
        _links[path] = (url: url, at: _clock());
        return url;
      } finally {
        _inFlight.remove(path);
      }
    }();
  }
}
