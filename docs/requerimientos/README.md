# Requerimientos funcionales (RF)

Conversión a Markdown del documento *Requerimientos Funcionales APP Veterinaria MASCOTI*. Cada archivo contiene el texto original y, al final, una sección **Adaptación a Firebase** que **prevalece** sobre el texto original. El documento original describe un backend REST con JWT propio; el proyecto usa Firebase Auth + Firestore + Cloud Functions.

| RF | Nombre | Semana | Ubicación |
|---|---|---|---|
| [RF-01](RF-01.md) | Registro de usuario | 1 | `core/auth` |
| [RF-02](RF-02.md) | Inicio de sesión con Google | 1 | `core/auth` |
| [RF-03](RF-03.md) | Cierre de sesión | 1 | `core/auth` |
| [RF-04](RF-04.md) | Perfil de atención de la clínica | 2 | `plugins/clinica` |
| [RF-05](RF-05.md) | Catálogo de servicios | 2 | `plugins/clinica` |
| [RF-06](RF-06.md) | Agenda (disponibilidad y precios) | 2 | `plugins/clinica` |
| [RF-07](RF-07.md) | Inventario (e-commerce) | 6 | `plugins/tienda` |
| [RF-08](RF-08.md) | Historial médico | 3 | `plugins/mascotas` |
| [RF-09](RF-09.md) | Directorio georreferenciado | 3 | `plugins/directorio` |
| [RF-10](RF-10.md) | Botón SOS | 7 | `plugins/sos` |
| [RF-11](RF-11.md) | Chatbot | 7 (recortable) | `plugins/chatbot` |
| [RF-12](RF-12.md) | Tienda digital (compra) | 6 | `plugins/tienda` |
| [RF-13](RF-13.md) | Notificaciones push | 4 | `core/notificaciones` + `functions` |
| [RF-14](RF-14.md) | Reservas y aprobación de citas | 4 | `plugins/reservas` |
| [RF-15](RF-15.md) | Chat en tiempo real | 5 | `plugins/chat` |
| [RF-16](RF-16.md) | Adjuntos clínicos en el chat | 5 | `plugins/chat` |
| [RF-17](RF-17.md) | Placa QR | 7 | `plugins/utilidades` |
| [RF-18](RF-18.md) | Carnet / certificado PDF | 7 | `plugins/utilidades` + `functions` |

## Referencias cruzadas erróneas en el documento original

- RF-04 (paso 8) dice "Directorio Georreferenciado (RF-10)" → es **RF-09**.
- RF-06 (paso 8) y RF-09 (postcondición) dicen "Agendamiento (RF-13)" → es **RF-14**.

## Funcionalidades necesarias que no tienen RF propio

- **Registro y edición de mascotas** (dueño): nombre, especie, raza, fecha de nacimiento, foto, alergias, contacto de emergencia. Lo necesitan RF-08, RF-14, RF-17 y RF-18.
- **Creación de registros médicos** (clínica): diagnóstico, tratamiento, vacunas (con `fechaProximaDosis` y lote), adjuntos. Lo necesitan RF-08, RF-13 y RF-18.
- **Horario base de la clínica** (hora de apertura y cierre, duración del slot) para RF-06, y el campo `atencionEmergencias` para RF-10.

Se planifican en la semana 3 (ver [`../plan.md`](../plan.md)).

> **Cambio de alcance 3 (accesibilidad y modo oscuro):** aplica a todos los RF. Toda pantalla debe cumplir WCAG 2.1 AA (contraste, 48 dp, etiquetas para el lector, texto hasta 200 %, estados no solo por color) y funcionar en modo claro, oscuro y alto contraste. Ver [accesibilidad.md](../accesibilidad.md).
