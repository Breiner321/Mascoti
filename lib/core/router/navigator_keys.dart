import 'package:flutter/widgets.dart';

/// Navegador raíz: los plugins lo usan con `parentNavigatorKey` para abrir
/// pantallas a pantalla completa (sin barra inferior), p. ej. un chat o un
/// paso obligatorio. Vive aparte de app_router.dart para que los plugins no
/// importen el router (que conoce el manifiesto de plugins).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
