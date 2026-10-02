# Stack tecnológico de Mascoti

Criterio de selección: **un solo lenguaje para la app, cero servidores que administrar y el mínimo de piezas**, para que 3 personas entreguen 18 RF en 8 semanas con apoyo de Claude Code.

## Resumen

| Capa | Tecnología | Lenguaje | Por qué |
|---|---|---|---|
| App móvil (APK) | **Flutter 3** + Material 3 | **Dart 3** | Los RF ya la mencionan (`google_sign_in`, `qr_flutter`); un código para Android (y web/iOS en el futuro); los mockups se construyen rápido con widgets. |
| Estado + inyección de dependencias | **flutter_riverpod** (sin generadores) | Dart | Encaja con el microkernel: cada plugin expone sus providers; fácil de probar con `ProviderContainer` y *overrides*. |
| Navegación | **go_router** | Dart | Cada plugin aporta sus rutas; redirección por sesión/rol; *deep links* desde notificaciones push. |
| Autenticación | **Firebase Auth** (proveedor Google) + `google_sign_in` | — | Tokens, renovación y revocación incluidos. Reemplaza el JWT/refresh token propio del documento. |
| Base de datos | **Cloud Firestore** | — | Tiempo real (`snapshots()`), transacciones, modo offline incluido. |
| Archivos | **Cloud Storage for Firebase** | — | Fotos de productos, adjuntos del chat, PDF. |
| Lógica de servidor | **Cloud Functions for Firebase (2ª gen)** | **TypeScript** (Node 22) | Registro atómico + roles, pagos (webhook), push programado (FCM), PDF con `pdf-lib`, vista pública del QR. |
| Notificaciones | **Firebase Cloud Messaging** | — | RF-13. |
| Mapas | **Google Maps SDK** (`google_maps_flutter`) + **Places API** + `geolocator` + `geoflutterfire_plus` (geohash) | Dart | RF-01, RF-09, RF-10. |
| Pagos | **Wompi** (sandbox) | TypeScript (webhook) | Pasarela colombiana; RF-12. |
| Chatbot (opcional) | Árbol de decisión local → Dialogflow ES si hay tiempo | Dart / TS | RF-11 es el primer candidato a recorte. |
| Pruebas | `flutter_test`, `mocktail`, `fake_cloud_firestore`, `firebase_auth_mocks`; `@firebase/rules-unit-testing` + `vitest` para reglas/Functions | Dart / TS | |
| Emuladores | **Firebase Emulator Suite** | — | Desarrollo sin tocar datos reales. |
| CI | **GitHub Actions** | YAML | `analyze` + `test` en cada Pull Request. |

**Lenguajes que debe manejar el equipo:** Dart (95 % del trabajo) y TypeScript (Cloud Functions). Nada más.

## Paquetes de Flutter por semana

Se agregan con `flutter pub add <paquete>` cuando se necesiten (así se resuelven versiones compatibles automáticamente):

| Semana | Paquetes |
|---|---|
| 0–1 | `firebase_core firebase_auth cloud_firestore cloud_functions google_sign_in flutter_riverpod go_router intl` · dev: `mocktail fake_cloud_firestore firebase_auth_mocks` |
| 2 | `table_calendar` |
| 3 | `google_maps_flutter geolocator geoflutterfire_plus flutter_google_places_sdk firebase_storage image_picker` |
| 4 | `firebase_messaging flutter_local_notifications` |
| 5 | `file_picker` (adjuntos PDF) |
| 6 | `flutter_image_compress webview_flutter` (checkout Wompi) |
| 7 | `qr_flutter url_launcher share_plus shared_preferences` |

## Qué NO usamos (y por qué)

- **freezed / json_serializable / riverpod_generator:** requieren `build_runner`. Con tres personas y ramas en paralelo, los archivos generados causan conflictos. Los modelos se escriben a mano.
- **Backend REST propio (Express/Nest), JWT propio, Redis, PostGIS:** Firebase ya cubre esas funciones.
- **BLoC / GetX / Provider:** un solo patrón de estado (Riverpod) para todo el equipo.

## Planes y costos

- Con el **Emulator Suite** todo (incluidas las Functions) se desarrolla localmente gratis.
- **Cloud Functions y Cloud Scheduler requieren el plan Blaze** (pago por uso, con capa gratuita generosa). Activarlo en la semana 0/1 (la primera Function, `completarRegistro`, es de la semana 1) y **configurar una alerta de presupuesto** (p. ej. USD 5).
- Google Maps Platform: tiene una cuota gratuita mensual por API (Maps SDK Android, Places), suficiente para desarrollo; restringir la API key al paquete `co.mascoti.mascoti` + SHA-1.
