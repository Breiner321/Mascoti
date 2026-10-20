import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/data/medical_records_providers.dart';
import '../../../core/data/medical_records_repository.dart';
import '../../../core/domain/medical_record.dart';
import '../../../core/domain/pet.dart';
import '../../../core/theme/app_theme.dart';
import 'attachment_tile.dart';
import 'centered_message.dart';
import 'clinic_providers.dart';
import 'date_form_field.dart';
import 'medical_record_validators.dart';
import 'vaccine_fields.dart';

/// Nueva consulta ([recordId] null) o una consulta existente: la clínica
/// autora la corrige durante 24 h; después (o si es de otra clínica) se
/// muestra en solo lectura.
class MedicalRecordFormPage extends ConsumerWidget {
  const MedicalRecordFormPage({super.key, required this.petId, this.recordId});

  final String petId;
  final String? recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicId = ref.watch(currentUserProvider)?.clinicId ?? '';
    final pet = ref.watch(patientProvider(petId));
    final records = recordId == null ? null : ref.watch(medicalRecordsProvider(petId));
    final isNew = recordId == null;

    Widget scaffold(Widget body) => Scaffold(
          appBar: AppBar(title: Text(isNew ? 'Nueva consulta' : 'Consulta')),
          body: body,
        );

    if (pet.hasError || (records?.hasError ?? false)) {
      return scaffold(CenteredMessage(
        icon: Icons.cloud_off,
        text: 'No se pudo cargar la información.',
        action: FilledButton(
          onPressed: () {
            ref.invalidate(patientProvider(petId));
            ref.invalidate(medicalRecordsProvider(petId));
          },
          child: const Text('Reintentar'),
        ),
      ));
    }
    if (!pet.hasValue || (records != null && !records.hasValue)) {
      return scaffold(const Center(child: CircularProgressIndicator()));
    }
    final p = pet.value;
    if (p == null) {
      return scaffold(const CenteredMessage(
        icon: Icons.lock_outline,
        text: 'Ya no tienes acceso a esta mascota',
      ));
    }
    MedicalRecord? existing;
    if (!isNew) {
      existing = records!.value!.where((r) => r.id == recordId).firstOrNull;
      if (existing == null) {
        return scaffold(const CenteredMessage(
          icon: Icons.search_off,
          text: 'Esta consulta no existe',
        ));
      }
    }
    return MedicalRecordForm(
      // Una consulta distinta (o la misma tras guardar) crea un formulario nuevo.
      key: ValueKey(existing?.id ?? 'nueva'),
      pet: p,
      clinicId: clinicId,
      existing: existing,
    );
  }
}

/// Formulario de la consulta, ya con la mascota y la consulta cargadas.
class MedicalRecordForm extends ConsumerStatefulWidget {
  const MedicalRecordForm({
    super.key,
    required this.pet,
    required this.clinicId,
    this.existing,
  });

  final Pet pet;
  final String clinicId;
  final MedicalRecord? existing;

  @override
  ConsumerState<MedicalRecordForm> createState() => _MedicalRecordFormState();
}

class _MedicalRecordFormState extends ConsumerState<MedicalRecordForm> {
  final _formKey = GlobalKey<FormState>();
  late final DateTime _now;
  late final String _recordId;
  late final bool _readOnly;
  late DateTime _fecha;
  late final TextEditingController _diagnostico;
  late final TextEditingController _tratamiento;
  final List<VaccineDraft> _vacunas = [];
  final List<AttachmentDraft> _adjuntos = [];
  bool _saving = false;

  MedicalRecord? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    _now = ref.read(recordsClockProvider)();
    final existing = _existing;
    _recordId =
        existing?.id ?? ref.read(medicalRecordsRepositoryProvider).newRecordId(widget.pet.id);
    _readOnly =
        existing != null && (existing.clinicId != widget.clinicId || !existing.isEditable(_now));
    _fecha = existing?.fecha ?? _now;
    _diagnostico = TextEditingController(text: existing?.diagnostico ?? '');
    _tratamiento = TextEditingController(text: existing?.tratamiento ?? '');
    _vacunas.addAll([for (final v in existing?.vacunas ?? const <Vaccine>[]) VaccineDraft.from(v)]);
    _adjuntos.addAll([
      for (final a in existing?.adjuntos ?? const <RecordAttachment>[]) AttachmentDraft.saved(a),
    ]);
  }

  @override
  void dispose() {
    _diagnostico.dispose();
    _tratamiento.dispose();
    for (final v in _vacunas) {
      v.dispose();
    }
    super.dispose();
  }

  DateTime get _today => DateTime(_now.year, _now.month, _now.day);

  void _addVaccine() => setState(() {
        final day = DateTime(_fecha.year, _fecha.month, _fecha.day);
        _vacunas.add(VaccineDraft(fechaAplicacion: day));
      });

  void _removeVaccine(VaccineDraft draft) => setState(() {
        _vacunas.remove(draft);
        draft.dispose();
      });

  Future<void> _addAttachment() async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await ref.read(attachmentPickerProvider).pick();
    if (file == null || !mounted) return;
    final error = MedicalRecordValidators.adjunto(fileName: file.name, bytes: file.bytes.length);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final draft = AttachmentDraft.picked(
      nombre: MedicalRecordValidators.displayName(file.name),
      bytes: file.bytes,
      tipo: MedicalRecordValidators.attachmentType(file.name),
    );
    setState(() => _adjuntos.add(draft));
    await _upload(draft);
  }

  Future<void> _upload(AttachmentDraft draft) async {
    setState(() {
      draft.status = AttachmentStatus.uploading;
      draft.error = null;
    });
    try {
      final saved = await ref.read(medicalRecordsRepositoryProvider).uploadAttachment(
            petId: widget.pet.id,
            recordId: _recordId,
            fileName: draft.nombre,
            bytes: draft.bytes!,
          );
      if (!mounted) return;
      setState(() {
        draft.saved = saved;
        draft.status = AttachmentStatus.done;
      });
    } on MedicalRecordFailure catch (e) {
      if (mounted) setState(() => _fail(draft, e.message));
    } catch (_) {
      if (mounted) setState(() => _fail(draft, 'No se pudo subir el archivo. Intenta de nuevo.'));
    }
  }

  void _fail(AttachmentDraft draft, String message) {
    draft.status = AttachmentStatus.failed;
    draft.error = message;
  }

  Future<void> _openAttachment(AttachmentDraft draft) async {
    if (draft.tipo == AttachmentType.pdf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La vista previa está disponible solo para imágenes')),
      );
      return;
    }
    final bytes = draft.bytes;
    final path = draft.saved?.path;
    final Future<ImageProvider> image = bytes != null
        ? Future.value(MemoryImage(bytes))
        : ref
            .read(medicalRecordsRepositoryProvider)
            .attachmentUrl(petId: widget.pet.id, path: path!)
            .then((url) => NetworkImage(url));
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<ImageProvider>(
          future: image,
          builder: (context, snap) => switch (snap) {
            AsyncSnapshot(hasData: true, :final data) => InteractiveViewer(
                child: Image(
                  image: data!,
                  errorBuilder: (_, __, ___) => const _Unavailable(),
                ),
              ),
            AsyncSnapshot(hasError: true) => const _Unavailable(),
            _ => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
          },
        ),
      ),
    );
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_adjuntos.any((a) => a.status == AttachmentStatus.uploading)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Espera a que terminen de subir los adjuntos')),
      );
      return;
    }
    if (_adjuntos.any((a) => a.status == AttachmentStatus.failed)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Reintenta o quita los adjuntos que no se subieron')),
      );
      return;
    }

    final clinic = ref.read(clinicProvider(widget.clinicId)).value;
    final fields = (
      fecha: _fecha,
      diagnostico: _diagnostico.text.trim(),
      tratamiento: _tratamiento.text.trim(),
      vacunas: [for (final v in _vacunas) v.toVaccine()],
      adjuntos: [for (final a in _adjuntos) a.saved!],
    );
    final repo = ref.read(medicalRecordsRepositoryProvider);
    final existing = _existing;

    setState(() => _saving = true);
    try {
      if (existing == null) {
        await repo.createRecord(
          MedicalRecord(
            id: _recordId,
            petId: widget.pet.id,
            clinicId: widget.clinicId,
            clinicNombre: clinic?.nombre ?? '',
            fecha: fields.fecha,
            diagnostico: fields.diagnostico,
            tratamiento: fields.tratamiento,
            vacunas: fields.vacunas,
            adjuntos: fields.adjuntos,
          ),
          ownerUid: widget.pet.ownerUid,
        );
      } else {
        await repo.updateRecord(
          existing.copyWith(
            fecha: fields.fecha,
            diagnostico: fields.diagnostico,
            tratamiento: fields.tratamiento,
            vacunas: fields.vacunas,
            adjuntos: fields.adjuntos,
          ),
          previous: existing,
          ownerUid: widget.pet.ownerUid,
        );
      }
    } on MedicalRecordFailure catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
        content: Text(e == MedicalRecordFailure.denied && existing != null
            ? 'Ya no se puede corregir: pasaron más de 24 horas desde que se registró.'
            : e.message),
      ));
      return;
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo guardar la consulta. Intenta de nuevo.')),
      );
      return;
    }
    messenger.showSnackBar(SnackBar(
      backgroundColor: AppColors.success,
      content: Text(
        existing == null ? 'Consulta guardada' : 'Consulta actualizada',
        style: const TextStyle(color: AppColors.onPrimary),
      ),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = _existing;
    final readOnly = _readOnly || _saving;
    // Carga el nombre de la clínica para guardarlo en el registro.
    ref.watch(clinicProvider(widget.clinicId));

    return Scaffold(
      appBar: AppBar(title: Text(existing == null ? 'Nueva consulta' : 'Consulta')),
      bottomNavigationBar: _readOnly
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(existing == null ? 'Guardar consulta' : 'Guardar cambios'),
                ),
              ),
            ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.pet.nombre,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (existing != null && existing.clinicNombre.isNotEmpty)
              Text(
                'Registrada por ${existing.clinicNombre}',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            if (_readOnly) ...[
              const SizedBox(height: 12),
              _ReadOnlyBanner(
                text: existing!.clinicId != widget.clinicId
                    ? 'Registrada por otra clínica: solo lectura.'
                    : 'Solo lectura: las consultas se pueden corregir durante las '
                        '24 horas siguientes a su registro.',
              ),
            ],
            const SizedBox(height: 16),
            DateFormField(
              label: 'Fecha de la consulta',
              value: _fecha,
              enabled: !readOnly,
              firstDate: DateTime(2000),
              lastDate: _today,
              // Hoy conserva la hora actual; otro día queda al mediodía.
              onChanged: (d) => setState(() {
                if (d == null) return;
                final sameDay = d.year == _now.year && d.month == _now.month && d.day == _now.day;
                _fecha = sameDay ? _now : DateTime(d.year, d.month, d.day, 12);
              }),
              validator: (d) => MedicalRecordValidators.fecha(d, _now),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _diagnostico,
              enabled: !readOnly,
              minLines: 2,
              maxLines: 6,
              maxLength: MedicalRecordLimits.maxDiagnostico,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Diagnóstico *',
                alignLabelWithHint: true,
              ),
              validator: MedicalRecordValidators.diagnostico,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _tratamiento,
              enabled: !readOnly,
              minLines: 2,
              maxLines: 6,
              maxLength: MedicalRecordLimits.maxTratamiento,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Tratamiento',
                alignLabelWithHint: true,
              ),
              validator: MedicalRecordValidators.tratamiento,
            ),
            const SizedBox(height: 16),
            _SectionTitle(
              title: 'Vacunas aplicadas',
              action: readOnly || _vacunas.length >= MedicalRecordLimits.maxVacunas
                  ? null
                  : TextButton.icon(
                      onPressed: _addVaccine,
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar vacuna'),
                    ),
            ),
            if (_vacunas.isEmpty) const _EmptyHint('Sin vacunas en esta consulta'),
            for (var i = 0; i < _vacunas.length; i++)
              VaccineFields(
                key: _vacunas[i].key,
                index: i,
                draft: _vacunas[i],
                now: _now,
                readOnly: readOnly,
                onRemove: () => _removeVaccine(_vacunas[i]),
              ),
            const SizedBox(height: 16),
            _SectionTitle(
              title: 'Adjuntos',
              action: readOnly || _adjuntos.length >= MedicalRecordLimits.maxAdjuntos
                  ? null
                  : TextButton.icon(
                      onPressed: _addAttachment,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Adjuntar'),
                    ),
            ),
            if (!readOnly)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Radiografías y exámenes: imagen JPG/PNG o PDF de máximo 10 MB.',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ),
            if (_adjuntos.isEmpty) const _EmptyHint('Sin adjuntos'),
            for (final a in _adjuntos)
              AttachmentTile(
                key: a.key,
                draft: a,
                readOnly: readOnly,
                onRetry: () => _upload(a),
                onRemove: () => setState(() => _adjuntos.remove(a)),
                onOpen: () => _openAttachment(a),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            if (action != null) action!,
          ],
        ),
      );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        ),
      );
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.slotLockedContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, color: AppColors.slotLocked),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, size: 48, color: AppColors.textMuted),
              SizedBox(height: 8),
              Text('Archivo no disponible'),
            ],
          ),
        ),
      );
}
