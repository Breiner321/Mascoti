import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/auth/domain/session_state.dart';
import 'package:mascoti/core/kernel/plugin_registry.dart';
import 'package:mascoti/core/router/core_routes.dart';
import 'package:mascoti/core/router/redirect.dart';

import 'fake_plugins.dart';

void main() {
  final registry = PluginRegistry([
    FakePlugin('mascotas', roles: {UserRole.dueno}, tabs: [tab('/mascotas', 0)]),
    FakePlugin('clinica', roles: {UserRole.clinica}, tabs: [tab('/clinica', 0)]),
  ]);

  const owner = AppUser(
    uid: 'u1',
    email: 'a@b.co',
    displayName: 'Ana',
    role: UserRole.dueno,
    nombre: 'Ana Pérez',
    telefono: '3001234567',
  );

  String? go(SessionState s, String location) =>
      resolveRedirect(session: s, location: location, registry: registry);

  test('cargando → splash', () {
    expect(go(const SessionLoading(), '/mascotas'), CoreRoutes.splash);
    expect(go(const SessionLoading(), CoreRoutes.splash), isNull);
  });

  test('sin sesión → bienvenida', () {
    expect(go(const SignedOut(), '/mascotas'), CoreRoutes.welcome);
    expect(go(const SignedOut(), CoreRoutes.welcome), isNull);
  });

  test('sin perfil → registro', () {
    const s = NeedsRegistration(uid: 'u1', email: 'a@b.co');
    expect(go(s, CoreRoutes.welcome), CoreRoutes.registration);
  });

  test('suspendido → pantalla de suspensión', () {
    expect(go(const Suspended(), '/mascotas'), CoreRoutes.suspended);
  });

  test('con sesión: de bienvenida/registro al home del rol', () {
    expect(go(const SignedIn(owner), CoreRoutes.welcome), '/mascotas');
    expect(go(const SignedIn(owner), CoreRoutes.registration), '/mascotas');
  });

  test('con sesión: no puede entrar a plugins de otro rol', () {
    expect(go(const SignedIn(owner), '/clinica'), '/mascotas');
    expect(go(const SignedIn(owner), '/no-existe'), '/mascotas');
  });

  test('con sesión: rutas propias y del core permitidas', () {
    expect(go(const SignedIn(owner), '/mascotas'), isNull);
    expect(go(const SignedIn(owner), CoreRoutes.profile), isNull);
  });

  group('paso obligatorio de un plugin (RF-01 paso 14)', () {
    const clinic = AppUser(
      uid: 'v1',
      email: 'v@b.co',
      displayName: 'Vet',
      role: UserRole.clinica,
      clinicId: 'c1',
    );
    const setup = '/clinica/perfil-atencion';

    String? goStep(String location, AsyncValue<String?> step) => resolveRedirect(
          session: const SignedIn(clinic),
          location: location,
          registry: registry,
          pendingStep: step,
        );

    test('mientras el plugin decide → splash', () {
      expect(goStep(CoreRoutes.registration, const AsyncLoading()), CoreRoutes.splash);
      expect(goStep(CoreRoutes.splash, const AsyncLoading()), isNull);
    });

    test('con paso pendiente solo se permite ese paso y /perfil', () {
      expect(goStep(CoreRoutes.registration, const AsyncData(setup)), setup);
      expect(goStep(CoreRoutes.splash, const AsyncData(setup)), setup);
      expect(goStep('/clinica', const AsyncData(setup)), setup);
      // RF-04: ni el resto del panel ni las reservas de la clínica.
      expect(goStep('/clinica/servicios', const AsyncData(setup)), setup);
      expect(goStep('/reservas', const AsyncData(setup)), setup);
      expect(goStep(setup, const AsyncData(setup)), isNull);
      expect(goStep(CoreRoutes.profile, const AsyncData(setup)), isNull);
    });

    test('sin paso pendiente → comportamiento normal', () {
      expect(goStep(setup, const AsyncData(null)), isNull);
      expect(goStep(CoreRoutes.splash, const AsyncData(null)), '/clinica');
      expect(goStep('/mascotas', const AsyncData(null)), '/clinica');
    });
  });

  group('Cambio 1: "Completa tu perfil"', () {
    const legacy = AppUser(uid: 'u2', email: 'b@b.co', displayName: 'Beto G', role: UserRole.dueno);
    const clinic = AppUser(
      uid: 'v1', email: 'v@b.co', displayName: 'Vet', role: UserRole.clinica, clinicId: 'c1');

    test('un dueño sin nombre va a completar su perfil desde cualquier pantalla', () {
      for (final location in ['/mascotas', CoreRoutes.profile, CoreRoutes.welcome, '/clinica']) {
        expect(go(const SignedIn(legacy), location), CoreRoutes.completeProfile, reason: location);
      }
      expect(go(const SignedIn(legacy), CoreRoutes.completeProfile), isNull);
      // Antes que cualquier paso obligatorio de un plugin (p. ej. onboarding).
      expect(
        resolveRedirect(
          session: const SignedIn(legacy),
          location: '/mascotas',
          registry: registry,
          pendingStep: const AsyncData('/mascotas/bienvenida'),
        ),
        CoreRoutes.completeProfile,
      );
    });

    test('con nombre sale de la pantalla y la clínica nunca la ve', () {
      expect(go(const SignedIn(owner), CoreRoutes.completeProfile), '/mascotas');
      expect(go(const SignedIn(clinic), '/clinica'), isNull);
      expect(go(const SignedIn(clinic), CoreRoutes.completeProfile), '/clinica');
    });

    test('editar perfil es una ruta del core dentro de la app', () {
      expect(go(const SignedIn(owner), CoreRoutes.editProfile), isNull);
    });
  });
}
