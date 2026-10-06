# Stack tecnológico de Mascoti

Criterio de selección: **un solo lenguaje para la app, cero servidores que administrar y el mínimo de piezas**, para que 3 personas entreguen 18 RF en 8 semanas con apoyo de Claude Code.

> **Firebase (plan gratuito Spark) + Supabase (plan gratuito) + OpenStreetMap.** Firebase Spark no permite Cloud Functions ni crear Storage, y Google Maps/Places exigen cuenta de facturación. Por eso: **Firebase** para login, base de datos y push; **Supabase** para archivos y lógica de servidor (Edge Functions); **OpenStreetMap** para direcciones y mapas. Decisión del equipo, oct 2026.

## Resumen

| Capa | Tecnología | Lenguaje | Por qué |
|---|---|---|---|
| App móvil (APK) | **Flutter 3** + Material 3 | **Dart 3** | Los RF ya la mencionan (`google_sign_in`, `qr_flutter`); un código para Android (y web/iOS en el futuro); los mockups se construyen rápido con widgets. |
| Estado + inyección de dependencias | **flutter_riverpod** (sin generadores) | Dart | Encaja con el microkernel: cada plugin expone sus providers; fácil de probar con `ProviderContainer` y *overrides*. |
| Navegación | **go_router** | Dart | Cada plugin aporta sus rutas; redirección por sesión/rol; *deep links* desde notificaciones push. |
| Autenticación | **Firebase Auth** (proveedor Google) + `google_sign_in` | — | Tokens, renovación y revocación incluidos. Reemplaza el JWT/refresh token propio del documento. |
| Base de datos | **Cloud Firestore** | — | Tiempo real (`snapshots()`), transacciones, modo offline incluido. |
| Archivos | **Supabase Storage** (bucket privado `mascoti`) | SQL (políticas) | Fotos de productos, adjuntos del chat, PDF. Acepta el login de Firebase (Third-party Auth). |
| Lógica de servidor | **Supabase Edge Functions** (`supabase/functions/`) | **TypeScript** (Deno) | Registro atómico + roles, pagos (webhook), push programado (FCM), PDF, vista pública del QR. Escriben en Firestore con su API REST y una cuenta de servicio. |
| Notificaciones | **Firebase Cloud Messaging** | — | RF-13. |
| Mapas y direcciones | **OpenStreetMap**: búsqueda con **Photon** (`core/places`), mapa con `flutter_map` + `geolocator` + `geoflutterfire_plus` (geohash) | Dart | RF-01, RF-09, RF-10. Gratis y sin API key. |
| Pagos | **Wompi** (sandbox) | TypeScript (webhook) | Pasarela colombiana; RF-12. |
| Chatbot (opcional) | Árbol de decisión local → Dialogflow ES si hay tiempo | Dart / TS | RF-11 es el primer candidato a recorte. |
| Pruebas | `flutter_test`, `mocktail`, `fake_cloud_firestore`, `firebase_auth_mocks`; `@firebase/rules-unit-testing` + `vitest` para reglas y la lógica de las Edge Functions; `deno check` | Dart / TS | |
| Emuladores | **Firebase Emulator Suite** (Auth + Firestore) | — | Desarrollo sin tocar datos reales. |
| CI | **GitHub Actions** | YAML | `analyze` + `test` en cada Pull Request. |

**Lenguajes que debe manejar el equipo:** Dart (95 % del trabajo) y TypeScript (Edge Functions). Un poco de SQL para las políticas de Storage.

## Paquetes de Flutter por semana

Se agregan con `flutter pub add <paquete>` cuando se necesiten (así se resuelven versiones compatibles automáticamente):

| Semana | Paquetes |
|---|---|
| 0–1 | `firebase_core firebase_auth cloud_firestore cloud_functions google_sign_in flutter_riverpod go_router intl` · dev: `mocktail fake_cloud_firestore firebase_auth_mocks` |
| 2 | `table_calendar` |
| 3 | `flutter_map latlong2 geolocator geoflutterfire_plus image_picker` (Storage ya está en `core/storage` con `supabase_flutter`) |
| 4 | `firebase_messaging flutter_local_notifications` |
| 5 | `file_picker` (adjuntos PDF) |
| 6 | `flutter_image_compress webview_flutter` (checkout Wompi) |
| 7 | `qr_flutter url_launcher share_plus shared_preferences` |

## Qué NO usamos (y por qué)

- **freezed / json_serializable / riverpod_generator:** requieren `build_runner`. Con tres personas y ramas en paralelo, los archivos generados causan conflictos. Los modelos se escriben a mano.
- **Backend REST propio (Express/Nest), JWT propio, Redis, PostGIS:** Firebase + Supabase ya cubren esas funciones.
- **Base de datos de Supabase (Postgres) para datos de la app:** los datos siguen en Firestore; Supabase solo aporta Storage y Edge Functions.
- **BLoC / GetX / Provider:** un solo patrón de estado (Riverpod) para todo el equipo.

## Planes y costos

- **Firebase Spark (gratis):** Auth, Firestore (50 000 lecturas/día) y Cloud Messaging. No incluye Cloud Functions ni Storage.
- **Supabase Free:** 1 GB de Storage y 500 000 invocaciones de Edge Functions al mes. El proyecto se pausa tras 7 días sin uso (se reactiva desde el panel).
- **OpenStreetMap / Photon:** gratis, con uso justo. Si la app crece, se cambia la URL de `OsmAddressService` por una instancia propia o un proveedor pago, sin tocar pantallas.
- Si más adelante activan Firebase Blaze, se puede volver a Cloud Functions: la lógica de `supabase/functions/_shared` es TypeScript sin dependencias.
