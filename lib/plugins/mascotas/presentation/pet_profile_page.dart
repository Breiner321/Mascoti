import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/domain/pet.dart';
import '../../../core/theme/app_theme.dart';
import '../mascotas_routes.dart';
import 'pets_providers.dart';
import 'widgets/pet_avatar.dart';

/// Perfil de una mascota: datos, y pestañas preparadas para el historial
/// médico (RF-08) y los documentos (RF-17/18).
class PetProfilePage extends ConsumerWidget {
  const PetProfilePage({super.key, required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pet = ref.watch(petProvider(petId));
    final loaded = pet.value;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(loaded?.nombre ?? 'Mascota'),
          actions: [
            if (loaded != null)
              TextButton.icon(
                onPressed: () => context.push(MascotasRoutes.edit(petId)),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar'),
              ),
          ],
          bottom: loaded == null
              ? null
              : const TabBar(
                  tabs: [
                    Tab(text: 'Datos'),
                    Tab(text: 'Historial médico'),
                    Tab(text: 'Documentos'),
                  ],
                ),
        ),
        body: switch (pet) {
          AsyncValue(value: final Pet p) => TabBarView(
              children: [
                _PetDetails(pet: p),
                const _ComingSoonTab(
                  icon: Icons.medical_information_outlined,
                  text: 'Aquí verás las consultas, vacunas y tratamientos de tu mascota.',
                ),
                const _ComingSoonTab(
                  icon: Icons.description_outlined,
                  text: 'Aquí encontrarás el carnet de vacunas y la placa QR de tu mascota.',
                ),
              ],
            ),
          AsyncData() => const _Centered(child: Text('No encontramos esta mascota.')),
          AsyncError() => _Centered(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No pudimos cargar la mascota. Verifica tu conexión.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => ref.invalidate(petProvider(petId)),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          _ => const _Centered(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _PetDetails extends StatelessWidget {
  const _PetDetails({required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();
    final birth = pet.fechaNacimiento;
    final contact = pet.contactoEmergencia;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        Center(child: PetAvatar(photoPath: pet.fotoPath, size: 112)),
        const SizedBox(height: 12),
        Text(
          pet.nombre,
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          pet.summary(now),
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        _Info(label: 'Especie', value: pet.especie.label),
        _Info(label: 'Raza', value: pet.raza ?? 'Sin registrar'),
        _Info(label: 'Sexo', value: pet.sexoTexto),
        _Info(
          label: 'Fecha de nacimiento',
          value: birth == null
              ? 'Sin registrar'
              : MaterialLocalizations.of(context).formatMediumDate(birth),
        ),
        _Tags(title: 'Alergias', values: pet.alergias, empty: 'Sin alergias registradas'),
        _Tags(
          title: 'Condiciones',
          values: pet.condiciones,
          empty: 'Sin condiciones registradas',
        ),
        _Info(
          label: 'Contacto de emergencia',
          value: contact == null ? 'Sin registrar' : '${contact.nombre} · ${contact.telefono}',
        ),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
      subtitle: Text(value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.textPrimary)),
    );
  }
}

class _Tags extends StatelessWidget {
  const _Tags({required this.title, required this.values, required this.empty});

  final String title;
  final List<String> values;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 4),
          if (values.isEmpty)
            Text(empty, style: textTheme.bodyLarge?.copyWith(color: AppColors.textPrimary))
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [for (final v in values) Chip(label: Text(v))],
            ),
        ],
      ),
    );
  }
}

/// Pestaña vacía de una funcionalidad de semanas siguientes.
class _ComingSoonTab extends StatelessWidget {
  const _ComingSoonTab({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return _Centered(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text('Próximamente', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Center(child: Padding(padding: const EdgeInsets.all(24), child: child));
}
