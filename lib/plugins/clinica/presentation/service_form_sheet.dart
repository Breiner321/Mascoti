import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/clinic_service.dart';
import '../data/services_repository.dart';
import 'clinic_providers.dart';
import 'service_validators.dart';

/// Abre el formulario de servicio (RF-05). Sin [service] crea uno nuevo; con
/// [service] lo edita (precargado). Devuelve true si se guardó.
Future<bool?> showServiceFormSheet(
  BuildContext context, {
  required String clinicId,
  ClinicService? service,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ServiceFormSheet(clinicId: clinicId, service: service),
    );

/// Formulario de crear/editar servicio. Se queda abierto con los datos si
/// falla el guardado, para reintentar (RF-05, "Fallo de red al guardar").
class ServiceFormSheet extends ConsumerStatefulWidget {
  const ServiceFormSheet({
    super.key,
    required this.clinicId,
    this.service,
    this.saveTimeout = const Duration(seconds: 10),
  });

  final String clinicId;
  final ClinicService? service;

  /// Sin conexión Firestore deja la escritura en cola sin terminar; pasado
  /// este tiempo se ofrece reintentar.
  final Duration saveTimeout;

  @override
  ConsumerState<ServiceFormSheet> createState() => _ServiceFormSheetState();
}

class _ServiceFormSheetState extends ConsumerState<ServiceFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nombre = TextEditingController(text: widget.service?.nombre);
  late final _descripcion = TextEditingController(text: widget.service?.descripcion);
  late final _precio = TextEditingController(
    text: widget.service == null ? null : formatThousands(widget.service!.precio.round()),
  );
  late final _duracion = TextEditingController(
    text: widget.service?.duracionMin.toString(),
  );
  late ServiceCategory? _categoria = widget.service?.categoria;

  /// Id fijo durante la vida del formulario: un reintento escribe el mismo
  /// documento.
  late final String _id = widget.service?.id ??
      ref.read(servicesRepositoryProvider).newId(widget.clinicId);

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.service != null;

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _precio.dispose();
    _duracion.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final service = ClinicService(
      id: _id,
      nombre: _nombre.text.trim(),
      categoria: _categoria!,
      descripcion: _descripcion.text.trim(),
      precio: ServiceValidators.parsePrice(_precio.text)!.toDouble(),
      duracionMin: int.parse(_duracion.text.trim()),
    );

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(servicesRepositoryProvider)
          .save(widget.clinicId, service, isNew: !_isEdit)
          .timeout(widget.saveTimeout);
      if (mounted) Navigator.of(context).pop(true);
    } on ServicePermissionDenied {
      _fail('No tienes permisos para editar este catálogo.');
    } on TimeoutException {
      _fail('No se pudo guardar. Revisa tu conexión e inténtalo de nuevo.');
    } catch (_) {
      _fail('No se pudo guardar. Revisa tu conexión e inténtalo de nuevo.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionLabel = _error != null
        ? 'Reintentar'
        : _isEdit
            ? 'Actualizar'
            : 'Guardar';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(
              _isEdit ? 'Editar servicio' : 'Nuevo servicio',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nombre,
              enabled: !_saving,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nombre del servicio'),
              validator: ServiceValidators.nombre,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ServiceCategory>(
              initialValue: _categoria,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [
                for (final c in ServiceCategory.values)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: _saving ? null : (c) => setState(() => _categoria = c),
              validator: ServiceValidators.categoria,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descripcion,
              enabled: !_saving,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
              validator: ServiceValidators.descripcion,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _precio,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_ThousandsFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Precio',
                      prefixText: r'$ ',
                      suffixText: 'COP',
                    ),
                    validator: ServiceValidators.precio,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _duracion,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Duración',
                      suffixText: 'min',
                    ),
                    validator: ServiceValidators.duracion,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Deja solo dígitos y agrega puntos de miles mientras se escribe: 45000 →
/// 45.000.
class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final text = formatThousands(int.parse(digits));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
