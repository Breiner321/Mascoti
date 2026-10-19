import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/domain/pet.dart';
import '../../../core/theme/app_theme.dart';
import '../data/pet_photo_service.dart';
import '../data/pets_repository.dart';
import '../domain/pet_photo.dart';
import '../domain/pet_validators.dart';
import '../mascotas_routes.dart';
import 'date_label.dart';
import 'pets_providers.dart';
import 'widgets/pet_photo_field.dart';
import 'widgets/tag_chips_field.dart';

/// Registro ([petId] null) o edición de una mascota.
class PetFormPage extends ConsumerWidget {
  const PetFormPage({super.key, this.petId});

  final String? petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = petId;
    if (id == null) return const _PetForm(initial: null);

    final pet = ref.watch(petProvider(id));
    return switch (pet) {
      // Se toma la mascota una sola vez: los cambios que lleguen después
      // no deben borrar lo que el dueño está escribiendo.
      AsyncValue(:final Pet value) => _PetForm(key: ValueKey(id), initial: value),
      AsyncData() => const _Message(
          title: 'Editar mascota',
          text: 'No encontramos esta mascota.',
        ),
      AsyncError() => _Message(
          title: 'Editar mascota',
          text: 'No pudimos cargar la mascota. Verifica tu conexión.',
          onRetry: () => ref.invalidate(petProvider(id)),
        ),
      _ => const _Message(title: 'Editar mascota'),
    };
  }
}

class _PetForm extends ConsumerStatefulWidget {
  const _PetForm({super.key, required this.initial});

  /// null = mascota nueva.
  final Pet? initial;

  @override
  ConsumerState<_PetForm> createState() => _PetFormState();
}

class _PetFormState extends ConsumerState<_PetForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.initial?.nombre);
  late final _raza = TextEditingController(text: widget.initial?.raza);
  late final _contactoNombre =
      TextEditingController(text: widget.initial?.contactoEmergencia?.nombre);
  late final _contactoTelefono =
      TextEditingController(text: widget.initial?.contactoEmergencia?.telefono);
  late final _fechaText = TextEditingController();
  late final _sexoDetalle = TextEditingController(text: widget.initial?.sexoDetalle);

  late PetSpecies? _especie = widget.initial?.especie;
  late PetSex? _sexo = widget.initial?.sexo;
  late DateTime? _fechaNacimiento = widget.initial?.fechaNacimiento;
  late List<String> _alergias = [...?widget.initial?.alergias];
  late List<String> _condiciones = [...?widget.initial?.condiciones];
  PetPhoto? _photo;
  bool _processingPhoto = false;
  PetSaveStage? _stage;

  bool get _isNew => widget.initial == null;
  bool get _busy => _stage != null || _processingPhoto;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fechaText.text = _formatDate(_fechaNacimiento);
  }

  @override
  void dispose() {
    for (final c in [_nombre, _raza, _contactoNombre, _contactoTelefono, _fechaText, _sexoDetalle]) {
      c.dispose();
    }
    super.dispose();
  }

  String _formatDate(DateTime? date) =>
      date == null ? '' : dateLabel(context, date);

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaNacimiento ?? now,
      firstDate: DateTime(now.year - 40),
      lastDate: now,
      helpText: 'Fecha de nacimiento',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _fechaNacimiento = picked;
      _fechaText.text = _formatDate(picked);
    });
  }

  Future<void> _pickPhoto(PetPhotoSource source) async {
    final picker = ref.read(petPhotoPickerProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _processingPhoto = true);
    try {
      final photo = await picker.pick(source);
      if (photo != null && mounted) setState(() => _photo = photo);
    } on PetPhotoException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la cámara o la galería')),
      );
    } finally {
      if (mounted) setState(() => _processingPhoto = false);
    }
  }

  Pet _buildPet(PetsRepository repository, String ownerUid) {
    String? optional(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final contactoNombre = optional(_contactoNombre);
    final contactoTelefono = optional(_contactoTelefono);
    final initial = widget.initial;
    return Pet(
      id: initial?.id ?? repository.newPetId(),
      ownerUid: initial?.ownerUid ?? ownerUid,
      nombre: _nombre.text.trim(),
      especie: _especie!,
      raza: optional(_raza),
      sexo: _sexo,
      sexoDetalle: _sexo == PetSex.otro ? _sexoDetalle.text.trim() : null,
      fechaNacimiento: _fechaNacimiento,
      fotoPath: initial?.fotoPath,
      alergias: _alergias,
      condiciones: _condiciones,
      contactoEmergencia: contactoNombre == null || contactoTelefono == null
          ? null
          : EmergencyContact(nombre: contactoNombre, telefono: contactoTelefono),
      codigoPaciente: initial?.codigoPaciente,
      clinicasAutorizadas: initial?.clinicasAutorizadas ?? const [],
      createdAt: initial?.createdAt,
    );
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final owner = ref.read(currentUserProvider);
    if (owner == null) return;
    final repository = ref.read(petsRepositoryProvider);
    final selection = ref.read(selectedPetIdProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final isNew = _isNew;
    final pet = _buildPet(repository, owner.uid);
    final photo = _photo;

    setState(() => _stage = PetSaveStage.saving);
    try {
      final result = await repository.savePet(
        pet,
        isNew: isNew,
        photo: photo,
        onStage: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (isNew) selection.select(pet.id);
      if (result.photoFailed && photo != null) {
        _showPhotoError(messenger, () => repository.uploadPhoto(pet, photo));
      } else {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text(isNew ? 'Mascota registrada' : 'Cambios guardados',
                style: const TextStyle(color: AppColors.onPrimary)),
          ),
        );
      }
      if (isNew) {
        router.pushReplacement(MascotasRoutes.profile(pet.id));
      } else if (router.canPop()) {
        router.pop();
      }
    } on PetPermissionDenied {
      messenger.showSnackBar(
        const SnackBar(content: Text('No tienes permisos para guardar esta mascota')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo guardar. Intenta de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _stage = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _stage == null;
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Nueva mascota' : 'Editar mascota')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            PetPhotoField(
              photoPath: widget.initial?.fotoPath,
              photo: _photo,
              processing: _processingPhoto,
              enabled: enabled,
              onPick: _pickPhoto,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nombre,
              enabled: enabled,
              textCapitalization: TextCapitalization.words,
              maxLength: PetValidators.maxNombre,
              decoration: const InputDecoration(labelText: 'Nombre *'),
              validator: PetValidators.nombre,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<PetSpecies>(
              initialValue: _especie,
              decoration: const InputDecoration(labelText: 'Especie *'),
              items: [
                for (final s in PetSpecies.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: enabled ? (v) => setState(() => _especie = v) : null,
              validator: PetValidators.especie,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _raza,
              enabled: enabled,
              textCapitalization: TextCapitalization.sentences,
              maxLength: PetValidators.maxRaza,
              decoration: const InputDecoration(labelText: 'Raza'),
              validator: PetValidators.raza,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _fechaText,
              enabled: enabled,
              readOnly: true,
              onTap: _pickDate,
              decoration: InputDecoration(
                labelText: 'Fecha de nacimiento',
                suffixIcon: _fechaNacimiento == null
                    ? const Icon(Icons.calendar_today_outlined)
                    : IconButton(
                        tooltip: 'Quitar fecha',
                        icon: const Icon(Icons.clear),
                        onPressed: enabled
                            ? () => setState(() {
                                  _fechaNacimiento = null;
                                  _fechaText.clear();
                                })
                            : null,
                      ),
              ),
              validator: (_) =>
                  PetValidators.fechaNacimiento(_fechaNacimiento, DateTime.now()),
            ),
            const SizedBox(height: 16),
            Text('Sexo', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in PetSex.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _sexo == s,
                    onSelected: enabled
                        ? (on) => setState(() => _sexo = on ? s : null)
                        : null,
                  ),
              ],
            ),
            if (_sexo == PetSex.otro) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _sexoDetalle,
                enabled: enabled,
                maxLength: PetValidators.maxSexoDetalle,
                decoration: const InputDecoration(
                  labelText: 'Especifique',
                  hintText: 'Ej.: hermafrodita, no determinable',
                ),
                validator: PetValidators.sexoDetalle,
              ),
            ],
            const SizedBox(height: 24),
            TagChipsField(
              label: 'Alergias',
              hint: 'Ej.: pollo, penicilina',
              values: _alergias,
              enabled: enabled,
              onChanged: (v) => setState(() => _alergias = v),
            ),
            const SizedBox(height: 16),
            TagChipsField(
              label: 'Condiciones',
              hint: 'Ej.: diabetes, displasia de cadera',
              values: _condiciones,
              enabled: enabled,
              onChanged: (v) => setState(() => _condiciones = v),
            ),
            const SizedBox(height: 24),
            Text('Contacto de emergencia', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _contactoNombre,
              enabled: enabled,
              textCapitalization: TextCapitalization.words,
              maxLength: PetValidators.maxContactoNombre,
              decoration: const InputDecoration(labelText: 'Nombre del contacto'),
              validator: (v) =>
                  PetValidators.contactoNombre(v, _contactoTelefono.text),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _contactoTelefono,
              enabled: enabled,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Teléfono del contacto',
                hintText: '10 dígitos',
              ),
              validator: (v) =>
                  PetValidators.contactoTelefono(v, _contactoNombre.text),
            ),
            const SizedBox(height: 24),
            if (_stage case final stage?) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(stage.label, textAlign: TextAlign.center),
            ] else
              FilledButton(
                onPressed: _processingPhoto ? null : _save,
                child: Text(_isNew ? 'Registrar mascota' : 'Guardar cambios'),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Error al subir la foto" con Reintentar, hasta que la subida funcione.
/// Usa el ScaffoldMessenger de la app, así que sigue visible aunque se haya
/// cerrado el formulario.
void _showPhotoError(
  ScaffoldMessengerState messenger,
  Future<bool> Function() retry,
) {
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Error al subir la foto'),
      duration: const Duration(seconds: 10),
      action: SnackBarAction(
        label: 'Reintentar',
        onPressed: () async {
          if (await retry()) {
            messenger.showSnackBar(const SnackBar(content: Text('Foto guardada')));
          } else {
            _showPhotoError(messenger, retry);
          }
        },
      ),
    ),
  );
}

/// Pantalla de carga, error o mascota inexistente del modo edición.
class _Message extends StatelessWidget {
  const _Message({required this.title, this.text, this.onRetry});

  final String title;

  /// null = cargando.
  final String? text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final message = text;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: message == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message, textAlign: TextAlign.center),
                    if (onRetry != null) ...[
                      const SizedBox(height: 12),
                      FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
