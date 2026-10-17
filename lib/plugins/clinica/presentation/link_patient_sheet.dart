import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/domain/patient_code.dart';
import '../../../core/domain/pet.dart';
import '../../../core/theme/app_theme.dart';
import '../data/pet_link_api.dart';
import 'clinic_providers.dart';
import 'patient_avatar.dart';

/// Abre la hoja "Vincular paciente". Devuelve el petId si la clínica toca
/// "Ver perfil" después de vincular.
Future<String?> showLinkPatientSheet(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const LinkPatientSheet(),
    );

/// La clínica escribe el código MSC-XXXX que le da el dueño; la Edge
/// Function `vincular-mascota` la autoriza y devuelve la mascota, que se
/// muestra para confirmar que es la correcta.
class LinkPatientSheet extends ConsumerStatefulWidget {
  const LinkPatientSheet({super.key});

  @override
  ConsumerState<LinkPatientSheet> createState() => _LinkPatientSheetState();
}

class _LinkPatientSheetState extends ConsumerState<LinkPatientSheet> {
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;
  LinkedPet? _linked;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = PatientCode.normalize(_code.text);
    if (code == null) {
      // No gasta un intento del límite con un texto mal escrito.
      setState(() => _error = 'El código debe tener el formato MSC-XXXX.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final linked = await ref.read(petLinkApiProvider).link(code);
      await _saveOwnerName(linked);
      if (mounted) setState(() => _linked = linked);
    } on PetLinkFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// El nombre del dueño solo se usa para mostrarlo en la lista: si no se
  /// puede guardar, la vinculación igual quedó hecha.
  Future<void> _saveOwnerName(LinkedPet linked) async {
    final clinicId = ref.read(currentUserProvider)?.clinicId;
    if (clinicId == null) return;
    try {
      await ref.read(patientsRepositoryProvider).saveOwnerName(
            clinicId: clinicId,
            petId: linked.petId,
            duenoNombre: linked.duenoNombre,
          );
    } catch (_) {}
  }

  void _reset() => setState(() {
        _linked = null;
        _error = null;
        _code.clear();
      });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: _linked == null ? _buildForm(context) : _buildResult(context, _linked!),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Vincular paciente', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Escribe el código de paciente que te da el dueño. Lo encuentra en el '
          'perfil de su mascota.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          autofocus: true,
          enabled: !_loading,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
            LengthLimitingTextInputFormatter(10),
          ],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            labelText: 'Código de paciente',
            hintText: 'MSC-XXXX',
            prefixIcon: const Icon(Icons.qr_code_2),
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Vincular'),
        ),
      ],
    );
  }

  Widget _buildResult(BuildContext context, LinkedPet pet) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pet.nueva ? 'Paciente vinculado' : 'Este paciente ya estaba vinculado',
                style: theme.textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              PatientAvatar(photoPath: pet.fotoPath, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pet.nombre,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(PetSpecies.fromValue(pet.especie).label),
                    if (pet.duenoNombre.isNotEmpty) Text('Dueño: ${pet.duenoNombre}'),
                    Text(
                      pet.codigoPaciente,
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Verifica con el dueño que sea su mascota. El acceso se puede quitar '
          'desde la app del dueño en cualquier momento.',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(pet.petId),
          child: const Text('Ver perfil'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _reset, child: const Text('Vincular otro paciente')),
      ],
    );
  }
}
