# Cómo desarrollar Mascoti con Claude Code

## Principio

**Claude Code escribe el código y ustedes deciden y revisan.** La calidad depende de tres cosas: tareas pequeñas (un RF o menos), un plan aprobado antes de programar y un PR revisado por una persona.

## Ciclo de un RF (de 1 a 3 días)

```bash
# 1. Rama nueva desde main actualizado
git checkout main && git pull
git checkout -b feature/rf-05-catalogo-servicios

# 2. Abrir Claude Code en la raíz del repo
claude
```

Dentro de Claude Code:

```
/rf RF-05
```

El comando `/rf` (definido en `.claude/commands/rf.md`) hace que Claude:
1. lea el RF, `CLAUDE.md`, la arquitectura y el modelo de datos;
2. presente un **plan** (archivos, colecciones, reglas, pruebas) y **espere tu aprobación**;
3. implemente, pruebe (`flutter analyze`, `flutter test`) y haga commit.

Revisa el plan con cuidado: es el momento más barato para corregir. Si algo no cuadra, díselo antes de aprobar ("usa un bottom sheet en vez de un diálogo", "el precio es entero en COP").

```bash
# 3. Probar en el emulador o en el celular
flutter run --dart-define=USE_EMULATORS=true

# 4. Subir y abrir el PR
git push -u origin feature/rf-05-catalogo-servicios
gh pr create --fill        # o desde GitHub
```

## Tareas más pequeñas que un RF

Si un RF es grande (RF-14, RF-12), divídelo y pide cada parte por separado:

```
/rf RF-14 — solo la parte del dueño: selección de servicio, calendario y "Solicitar Cita". La bandeja de la clínica la hace otra persona.
```

## Pedidos útiles además de /rf

| Situación | Qué escribir |
|---|---|
| Pantalla desde el mockup | "Construye la pantalla 'Agendar cita' de `docs/mockups/mockups_Mascoti.pdf` (página 1, cuarta pantalla de VISTA CLIENTE) usando el tema de `core/theme`." |
| Error | Pega el error completo + "¿Por qué falla? Arréglalo y agrega una prueba que lo cubra." |
| Revisión antes del PR | "Revisa los cambios de esta rama contra CLAUDE.md: microkernel, reglas de seguridad, estados vacío/error y pruebas." |
| Reglas de seguridad | "Escribe pruebas de `firestore.rules` para `clinics/{id}/services` que demuestren que otra clínica no puede editar." |
| Conflictos de merge | "Resuelve los conflictos con main conservando ambos cambios; luego ejecuta analyze y test." |

## Buenas prácticas con Claude Code

- **Una sesión por tarea.** Al terminar un RF usa `/clear` antes de empezar el siguiente, para que no arrastre contexto viejo.
- **Modo plan** (Shift+Tab dos veces) para pensar sin tocar archivos cuando la tarea es ambigua.
- **No aceptes cambios en `core/`, `firestore.rules` o `functions/`** sin que los revise Dev A.
- Si Claude propone un paquete nuevo o un cambio de stack, **consúltalo con el equipo**; `docs/stack.md` es la referencia.
- Pídele siempre que ejecute las pruebas; no des por buena una tarea sin `flutter analyze` en 0.
- Si notas que Claude repite un error de criterio, **agrega la regla a `CLAUDE.md`** en un PR, y así el equipo entero se beneficia.

## Ramas y commits

- `main`: siempre compila y pasa pruebas. Protegida.
- `feature/rf-XX-descripcion`, `fix/descripcion`, `chore/descripcion`.
- Commits: `feat(clinica): RF-05 crear y editar servicios`, `fix(auth): ...`, `test(...)`, `docs(...)`.

## Evitar conflictos entre los 3

- Cada persona trabaja en **su carpeta de plugin**.
- Archivos compartidos que suelen chocar: `plugin_manifest.dart`, `firestore.rules`, `firestore.indexes.json`, `docs/modelo-datos.md`, `pubspec.yaml`. Hagan cambios pequeños ahí y hagan merge seguido (`git pull origin main` a diario).
- Paquetes nuevos: agrégalos con `flutter pub add` en un commit aparte.
