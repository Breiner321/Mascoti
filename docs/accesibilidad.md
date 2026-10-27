# Accesibilidad (Cambio 3)

Meta: **WCAG 2.1 nivel AA** en lo aplicable a una app móvil. Usable con lector de pantalla (TalkBack), con texto grande y por personas con baja visión o daltonismo.

## Qué tiene la app

| Tema | Cómo se resuelve | Dónde |
|---|---|---|
| Contraste | Cuatro paletas (claro = mockups, oscuro y sus versiones de alto contraste). Texto ≥ 4.5:1; controles e íconos ≥ 3:1 | `lib/core/theme/app_palette.dart`; prueba `test/core/theme/app_palette_test.dart` |
| Modo oscuro y alto contraste | Perfil → **Accesibilidad**. Se guarda en el teléfono. "Sistema" sigue al tema de Android | `lib/core/accessibility/` |
| Texto grande | La app funciona hasta 200 % (tamaño del sistema × tamaño de la app). El encabezado morado crece hasta 130 % (logo e íconos) | `MascotiApp`, pruebas "texto al 200 %" |
| Áreas táctiles | Mínimo 48×48 dp (botones del encabezado, celdas y flechas del calendario) | pruebas `androidTapTargetGuideline` |
| Etiquetas | Todo botón de solo ícono tiene `tooltip`; fotos "Foto de Luna"; flechas "Mes anterior/siguiente" | pruebas `labeledTapTargetGuideline` |
| No solo color | Estados de cita y de franja con ícono y texto; días con horas con un punto; "Próximamente" escrito | `AppointmentStatusChip`, `DayExceptionsView`, `BookingCalendar` |
| Movimiento | Respeta "Quitar animaciones" de Android y la opción "Reducir animaciones" de la app (cambio de pantalla sin animación) | `AppTheme.of(reduceMotion:)` |
| SOS | 48 dp, ícono + texto, se anuncia "SOS: emergencia veterinaria" y es lo primero del encabezado para el lector | `lib/core/widgets/sos_button.dart` |

### Reglas para el código nuevo
- Colores **solo** desde `AppColors` (lee la paleta activa). Nunca `Colors.white`, `Color(0x…)` ni colores guardados en `static final`: no cambiarían con el tema.
- Como `AppColors` ya no es constante, no se puede usar dentro de `const` (el analizador lo marca).
- Botones de solo ícono: siempre `tooltip`.
- Nada de alturas fijas para contenedores con texto: usa `minHeight`, `Wrap` o desplazamiento.
- Un estado nunca solo con color: agrega ícono o texto.
- En las pruebas de widget de pantallas nuevas agrega el grupo "accesibilidad" con `expectAccessible` y `useLargeText` (`test/a11y.dart`).

### Contrastes de la paleta clara (antes → después)

| Par | Antes | Después |
|---|---|---|
| `textMuted` sobre fondo | 3.95 ❌ | 5.65 ✅ |
| `textMuted` sobre tarjetas moradas | 3.59 ❌ | 5.14 ✅ |
| Blanco sobre `success` | 3.30 ❌ | 5.02 ✅ |
| "Libre" (verde) sobre su fondo | 3.00 ❌ | 4.57 ✅ |
| "Ocupada" (gris) sobre su fondo | 3.90 ❌ | 6.10 ✅ |
| Texto rojo sobre fondo rosado | 4.41 ❌ | 5.91 ✅ (`sosText`) |
| Borde de campos y chips | 1.23 ❌ | 3.39 ✅ (`outline`) |

## Verificación manual con TalkBack (antes de cada entrega)

Activa TalkBack: Ajustes → Accesibilidad → TalkBack (o mantén presionadas las dos teclas de volumen 3 s si está configurado el atajo). Navega deslizando a la derecha/izquierda y toca dos veces para activar.

**General**
- [ ] Cada botón se anuncia con su función ("Notificaciones, 2 sin leer", "Perfil", "Mes siguiente"); ninguno dice solo "botón".
- [ ] El orden de lectura sigue el orden visual (arriba → abajo, izquierda → derecha).
- [ ] Los títulos de sección se anuncian como encabezados (se puede saltar entre encabezados).
- [ ] Después de una acción (guardar, bloquear, solicitar) el aviso inferior se lee.

**Encabezado y SOS (dueño)**
- [ ] Al entrar al encabezado, lo primero que se anuncia es "SOS: emergencia veterinaria".
- [ ] Desde la parte superior de la pantalla se llega al SOS con un solo deslizamiento.

**Dueño**
- [ ] Inicio: "Foto de Luna", accesos con su nombre; los que no existen dicen "Próximamente".
- [ ] Agendar: cada hora se anuncia "9:30 a. m., disponible" y "seleccionado" al elegirla; el calendario anuncia el día completo ("viernes, 6 de noviembre de 2026").
- [ ] Mis citas: cada tarjeta incluye "Estado: Confirmada" (o el que corresponda).
- [ ] Notificaciones: las no leídas dicen "Sin leer".

**Clínica**
- [ ] Mi día: cada franja se anuncia "9:00 a. m., Libre", "Ocupada · Luna · Pendiente" o "Bloqueada · motivo"; las pasadas dicen "ya pasó".
- [ ] Perfil de atención: cada día anuncia "Abierto/Cerrado" y los chips "Abre 8:00 a. m.".

**Texto grande y tema**
- [ ] Ajustes → Pantalla → Tamaño de fuente al máximo: ninguna pantalla corta texto ni se superpone; se puede desplazar.
- [ ] Perfil → Accesibilidad → tamaño 150 %: igual.
- [ ] Modo oscuro y alto contraste: todos los textos se leen; no quedan zonas blancas.
- [ ] Ajustes → Accesibilidad → Quitar animaciones: las pantallas cambian sin animación.
