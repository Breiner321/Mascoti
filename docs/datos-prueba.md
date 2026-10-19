# Datos de prueba: historial médico (RF-08)

Para probar la línea de tiempo del dueño sin depender de que una clínica registre consultas, hay un script que llena el **emulador de Firestore** con datos de ejemplo. Nunca escribe en Firebase real: si encuentra `GOOGLE_APPLICATION_CREDENTIALS`, se detiene.

## Qué crea

Para el usuario con el que entres a la app:

| Documento | Contenido |
|---|---|
| `users/{uid}` | Dueño activo con el onboarding visto (el registro con `completar-registro` no acepta usuarios del emulador) |
| `clinics/clinica-demo` | "Clínica Veterinaria Demo", activa |
| `pets/{uid}-toby` | "Toby", perro criollo, código `MSC-DEMQ`, con la clínica demo en `clinicasAutorizadas` |
| `pets/{uid}-toby/medicalRecords` | 3 consultas: control anual con 2 vacunas (Rabia con próxima dosis, Parvovirus sin ella), cojera con 2 adjuntos (imagen y PDF) y una de hace un año sin tratamiento |
| `vacunasProgramadas/demo-vacunas_0` | Próxima dosis de la Rabia |

Los adjuntos de ejemplo **no existen** en Supabase, así que en la app se ven como **"Archivo no disponible"**: sirve para probar ese flujo alterno de RF-08. Para ver adjuntos reales hay que usar Firebase real y una clínica que los suba (registros médicos de la clínica).

## Pasos

1. Terminal 1, en la raíz del repo:
   ```powershell
   firebase emulators:start
   ```
2. Terminal 2: abre la app contra los emuladores y entra con Google. Como el usuario no está registrado en el emulador, la app se queda en "Crea tu cuenta"; no hace falta terminar el registro.
   ```powershell
   flutter run --dart-define=USE_EMULATORS=true --dart-define-from-file=env/dev.json
   ```
3. Copia el **User UID** de http://localhost:4000/auth.
4. Terminal 3, en `functions/`:
   ```powershell
   npm run seed:historial -- <uid>
   ```
   La app pasa sola al inicio del dueño con "Toby". Abre su perfil → pestaña **Historial médico**.
5. **Tiempo real:** con la pestaña abierta, ejecuta
   ```powershell
   npm run seed:historial -- <uid> --nueva
   ```
   La consulta nueva aparece arriba sin refrescar.

Se puede correr varias veces: reemplaza los mismos documentos (con `--nueva` agrega otra consulta cada vez). Los datos del emulador se borran al cerrarlo.

## Qué revisar

- Orden: la consulta más reciente arriba; la de hace un año al final.
- Tarjeta cerrada: fecha, clínica y diagnóstico. Al tocarla: tratamiento ("Sin tratamiento registrado" en la antigua), vacunas con lote y próxima dosis, y adjuntos.
- Adjuntos: "Archivo no disponible" con botón para reintentar, sin bloquear el resto del historial.
- Pestaña **Datos**: código `MSC-DEMQ` con botón para copiar, el texto "Compártelo con tu clínica para que pueda registrar consultas." y "Clínica Veterinaria Demo" en **Clínicas con acceso** (al quitarla, la mascota deja de tenerla en `clinicasAutorizadas`).
- Mascota sin consultas (registra otra): "Esta mascota aún no tiene historial médico registrado".
