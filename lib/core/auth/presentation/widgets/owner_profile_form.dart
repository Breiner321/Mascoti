import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth_providers.dart';
import '../../data/auth_repository.dart';
import '../../domain/registration.dart';

/// Nombre completo y teléfono del dueño (Cambio 1). Lo usan "Completa tu
/// perfil" y "Editar perfil". Llama a [onSaved] cuando se guardó.
class OwnerProfileForm extends ConsumerStatefulWidget {
  const OwnerProfileForm({
    super.key,
    required this.initialName,
    required this.initialPhone,
    required this.submitLabel,
    this.onSaved,
  });

  final String initialName;
  final String initialPhone;
  final String submitLabel;
  final VoidCallback? onSaved;

  @override
  ConsumerState<OwnerProfileForm> createState() => _OwnerProfileFormState();
}

class _OwnerProfileFormState extends ConsumerState<OwnerProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name =
      TextEditingController(text: RegistrationValidators.normalizeName(widget.initialName));
  late final _phone = TextEditingController(text: widget.initialPhone);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(authRepositoryProvider)
          .updateOwnerProfile(nombre: _name.text, telefono: _phone.text);
      widget.onSaved?.call();
    } on ProfileUpdateFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            enabled: !_saving,
            decoration: const InputDecoration(labelText: 'Nombre completo'),
            textCapitalization: TextCapitalization.words,
            maxLength: RegistrationValidators.maxOwnerName,
            validator: RegistrationValidators.ownerName,
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: _phone,
            enabled: !_saving,
            decoration: const InputDecoration(labelText: 'Teléfono (10 dígitos)'),
            keyboardType: TextInputType.phone,
            maxLength: 10,
            validator: RegistrationValidators.phone,
            autovalidateMode: AutovalidateMode.onUserInteraction,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}
