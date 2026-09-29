---
description: Implementa un requerimiento funcional de Mascoti (ej. /rf RF-05)
argument-hint: RF-XX [aclaraciones o alcance parcial]
---

Vas a implementar: **$ARGUMENTS**

Sigue estos pasos en orden:

1. **Contexto.** Lee `CLAUDE.md`, `docs/arquitectura.md`, `docs/modelo-datos.md` y el archivo del RF en `docs/requerimientos/` (incluida la sección "Adaptación a Firebase", que prevalece). Si el RF tiene una pantalla en `docs/mockups/mockups_Mascoti.pdf`, revísala. Revisa el código existente del plugin involucrado y de `lib/core/`.
2. **Plan (detente aquí).** Presenta:
   - plugin y archivos a crear o modificar;
   - colecciones/campos de Firestore y cambios en `firestore.rules`, `storage.rules` o `firestore.indexes.json`;
   - Cloud Functions necesarias (si aplica);
   - paquetes nuevos (si aplica, justificando);
   - pruebas que escribirás;
   - dudas o ambigüedades del RF.
   **Espera mi aprobación antes de escribir código.**
3. **Implementación.** Respeta el microkernel (sin imports entre plugins) y los textos, validaciones y flujos alternativos exactos del RF. Cubre los estados de carga, vacío y error.
4. **Pruebas.** Escribe las pruebas y ejecuta `flutter analyze` y `flutter test` (y `cd functions && npm test` si tocaste Functions o reglas) hasta que todo pase.
5. **Documentación.** Actualiza `docs/modelo-datos.md` si cambió el modelo y marca el RF como 🟨 en `docs/plan.md`.
6. **Commit** con el mensaje `feat(<plugin>): <RF> <descripción corta>`. No hagas push.
7. **Resumen final:** qué se hizo, cómo probarlo manualmente en la app y qué quedó pendiente.
