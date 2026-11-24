import 'package:go_router/go_router.dart';

import '../../core/auth/domain/app_user.dart';
import '../../core/kernel/mascoti_plugin.dart';
import '../../core/router/navigator_keys.dart';
import 'presentation/sos_page.dart';

/// Botón SOS de emergencia (RF-10), solo para el dueño. Se abre desde el
/// botón rojo del encabezado y el acceso "Emergencia" del home; no tiene
/// pestaña propia.
class SosPlugin extends MascotiPlugin {
  const SosPlugin();

  static const path = '/sos';

  @override
  String get id => 'sos';

  @override
  Set<UserRole> get roles => const {UserRole.dueno};

  @override
  List<RouteBase> routes() => [
        // Pantalla completa, sin encabezado ni barra inferior.
        GoRoute(
          path: path,
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const SosPage(),
        ),
      ];
}
