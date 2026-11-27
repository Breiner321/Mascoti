import 'dart:async';

/// Sin conexión, Firestore guarda la escritura en el teléfono y la envía
/// cuando vuelve la red, pero su Future no termina hasta entonces. Pasado
/// este tiempo la pantalla sigue como si se hubiera guardado y lo avisa con
/// [offlineWriteMessage], en vez de quedarse "guardando" para siempre.
const offlineWriteTimeout = Duration(seconds: 10);

const offlineWriteMessage = 'Sin conexión: se guardará cuando vuelva la red.';

/// Espera [write]: true si el servidor la confirmó, false si sigue en cola
/// (sin conexión). Los errores de [write] antes del tiempo se propagan.
Future<bool> awaitWrite(Future<void> write) =>
    write.then((_) => true).timeout(offlineWriteTimeout, onTimeout: () => false);
