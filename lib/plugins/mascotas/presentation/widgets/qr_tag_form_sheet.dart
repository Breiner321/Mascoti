import 'package:flutter/material.dart';

import '../../../../core/domain/pet.dart';
import '../../../../core/domain/qr_tag.dart';
import '../../../../core/theme/app_theme.dart';
import 'qr_tag_preview.dart';

/// Hoja "Crear placa QR" / "Qué se muestra": interruptores, mensaje y vista
/// previa. Devuelve lo elegido, o null si se cancela.
Future<QrTagDisplay?> showQrTagForm(
  BuildContext context, {
  required Pet pet,
  required String ownerName,
  required String? ownerPhone,
  QrTagDisplay initial = const QrTagDisplay(),
  required String submitLabel,
}) =>
    showModalBottomSheet<QrTagDisplay>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => QrTagFormSheet(
        pet: pet,
        ownerName: ownerName,
        ownerPhone: ownerPhone,
        initial: initial,
        submitLabel: submitLabel,
      ),
    );

class QrTagFormSheet extends StatefulWidget {
  const QrTagFormSheet({
    super.key,
    required this.pet,
    required this.ownerName,
    required this.ownerPhone,
    required this.initial,
    required this.submitLabel,
  });

  final Pet pet;
  final String ownerName;
  final String? ownerPhone;
  final QrTagDisplay initial;
  final String submitLabel;

  @override
  State<QrTagFormSheet> createState() => _QrTagFormSheetState();
}

class _QrTagFormSheetState extends State<QrTagFormSheet> {
  late QrTagDisplay _display = widget.initial;
  late final _mensaje = TextEditingController(text: widget.initial.mensaje);
  String? _error;

  bool get _hasPhone => (widget.ownerPhone?.trim() ?? '').isNotEmpty;

  @override
  void dispose() {
    _mensaje.dispose();
    super.dispose();
  }

  void _submit() {
    final display = _display.copyWith(mensaje: _mensaje.text.trim());
    final error = display.validate(hasPhoto: widget.pet.fotoPath != null, ownerHasPhone: _hasPhone);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(display);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Placa QR de ${widget.pet.nombre}',
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'El nombre, la especie y la foto se muestran siempre. Elige qué más verá quien la encuentre.',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mi nombre'),
            subtitle: Text(widget.ownerName),
            value: _display.nombreDueno,
            onChanged: (v) => setState(() => _display = _display.copyWith(nombreDueno: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mi teléfono'),
            subtitle: Text(_hasPhone
                ? 'Se ve oculto (${maskPhone(widget.ownerPhone!)}) hasta pulsar "Ver teléfono"'
                : 'No tienes teléfono en tu perfil'),
            value: _hasPhone && _display.telefono,
            onChanged: _hasPhone
                ? (v) => setState(() => _display = _display.copyWith(telefono: v))
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Alergias'),
            subtitle: Text(widget.pet.alergias.isEmpty
                ? 'Sin alergias registradas'
                : widget.pet.alergias.join(', ')),
            value: _display.alergias,
            onChanged: (v) => setState(() => _display = _display.copyWith(alergias: v)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _mensaje,
            maxLength: QrTagDisplay.maxMensaje,
            maxLines: 3,
            minLines: 1,
            onChanged: (v) => setState(() => _display = _display.copyWith(mensaje: v)),
            decoration: const InputDecoration(
              labelText: 'Mensaje (opcional)',
              hintText: 'Ej.: Hay recompensa. Necesita su medicina cada 8 horas.',
            ),
          ),
          const SizedBox(height: 8),
          QrTagPreview(
            pet: widget.pet,
            display: _display.copyWith(telefono: _hasPhone && _display.telefono),
            ownerName: widget.ownerName,
            ownerPhone: widget.ownerPhone,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.sosText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!,
                      style: textTheme.bodyMedium?.copyWith(color: AppColors.sosText)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
        ],
      ),
    );
  }
}
