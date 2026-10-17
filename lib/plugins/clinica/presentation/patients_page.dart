import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../clinica_routes.dart';
import '../domain/patient.dart';
import 'centered_message.dart';
import 'clinic_providers.dart';
import 'link_patient_sheet.dart';
import 'patient_tile.dart';

/// Pestaña "Pacientes": mascotas que autorizaron a la clínica, con buscador
/// y el botón para vincular una nueva con su código de paciente.
class PatientsPage extends ConsumerStatefulWidget {
  const PatientsPage({super.key});

  @override
  ConsumerState<PatientsPage> createState() => _PatientsPageState();
}

class _PatientsPageState extends ConsumerState<PatientsPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final petId = await showLinkPatientSheet(context);
    if (petId != null && mounted) context.push(ClinicaRoutes.patient(petId));
  }

  @override
  Widget build(BuildContext context) {
    final clinicId = ref.watch(currentUserProvider)?.clinicId;
    if (clinicId == null) {
      return const Center(child: Text('Tu cuenta no tiene una clínica asociada.'));
    }
    final patients = ref.watch(patientsProvider(clinicId));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _link,
        icon: const Icon(Icons.link),
        label: const Text('Vincular paciente'),
      ),
      body: switch (patients) {
        AsyncData(:final value) => _buildList(value),
        AsyncError() => CenteredMessage(
            icon: Icons.cloud_off,
            text: 'No se pudieron cargar tus pacientes.',
            action: FilledButton(
              onPressed: () => ref.invalidate(authorizedPetsProvider(clinicId)),
              child: const Text('Reintentar'),
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _buildList(List<Patient> all) {
    if (all.isEmpty) {
      return const CenteredMessage(
        icon: Icons.pets_outlined,
        text: 'Aún no tienes pacientes vinculados',
        detail: 'Pídele al dueño el código de paciente de su mascota (MSC-XXXX), '
            'que aparece en el perfil de la mascota en su app, y toca '
            '"Vincular paciente".',
      );
    }
    final visible = [
      for (final p in all)
        if (p.matches(_query)) p
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre, dueño o código',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
                    ),
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? CenteredMessage(
                  icon: Icons.search_off,
                  text: 'Ningún paciente coincide con "${_query.trim()}"',
                )
              : ListView.separated(
                  // Espacio abajo para que el botón flotante no tape la última fila.
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => PatientTile(
                    key: ValueKey(visible[i].pet.id),
                    patient: visible[i],
                    onTap: () => context.push(ClinicaRoutes.patient(visible[i].pet.id)),
                  ),
                ),
        ),
      ],
    );
  }
}
