import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../places/place_address.dart';
import '../../theme/app_theme.dart';
import '../../widgets/address_autocomplete_field.dart';
import '../auth_providers.dart';
import '../domain/app_user.dart';
import '../domain/registration.dart';
import '../domain/registration_failure.dart';
import '../domain/session_state.dart';
import 'widgets/role_card.dart';

/// RF-01: selección de rol (parte inferior del mockup LOGIN) y, si es Clínica,
/// datos del negocio con dirección de OpenStreetMap.
///
/// Al terminar, el router lleva al dueño a su home (con onboarding) y a la
/// clínica a /clinica/perfil-atencion (paso obligatorio del plugin clinica).
class RegistrationPage extends ConsumerStatefulWidget {
  const RegistrationPage({super.key});

  @override
  ConsumerState<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends ConsumerState<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  UserRole? _role;
  PlaceAddress? _address;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final role = _role;
    if (role == null) return;
    if (role == UserRole.clinica && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final address = _address;
    // El validador del campo ya lo impide; se repite por seguridad.
    if (role == UserRole.clinica && address == null) return;

    final request = address == null || role == UserRole.dueno
        ? const RegistrationRequest.owner()
        : RegistrationRequest.clinic(
            ClinicRegistration(
              nombre: _name.text,
              telefono: _phone.text,
              direccion: address.direccion,
              lat: address.lat,
              lng: address.lng,
            ),
          );

    setState(() => _submitting = true);
    try {
      await ref.read(authRepositoryProvider).completeRegistration(request);
      // Al crearse users/{uid}, sessionProvider cambia y el router redirige.
    } on RegistrationFailure catch (e) {
      _showMessage(e.message, retry: e.canRetry);
    } catch (_) {
      _showMessage(
        const RegistrationFailure(RegistrationFailureKind.network).message,
        retry: true,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String text, {bool retry = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        action: retry ? SnackBarAction(label: 'Reintentar', onPressed: _submit) : null,
      ),
    );
  }

  void _selectRole(UserRole role) => setState(() => _role = role);

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final email = session is NeedsRegistration ? session.email : '';
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            email,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                          ),
                        ),
                        TextButton(
                          onPressed: _submitting
                              ? null
                              : () => ref.read(authRepositoryProvider).signOut(),
                          child: const Text('Usar otra cuenta'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Crea tu cuenta',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '¿CÓMO USARÁS MASCOTI?',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    RoleCard(
                      role: UserRole.dueno,
                      selected: _role == UserRole.dueno,
                      onTap: _submitting ? null : () => _selectRole(UserRole.dueno),
                    ),
                    const SizedBox(height: 12),
                    RoleCard(
                      role: UserRole.clinica,
                      selected: _role == UserRole.clinica,
                      onTap: _submitting ? null : () => _selectRole(UserRole.clinica),
                    ),
                    if (_role == UserRole.clinica) ...[
                      const SizedBox(height: 24),
                      Text(
                        'DATOS DE LA CLÍNICA',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _name,
                        enabled: !_submitting,
                        decoration: const InputDecoration(labelText: 'Nombre comercial'),
                        textCapitalization: TextCapitalization.words,
                        validator: RegistrationValidators.clinicName,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        enabled: !_submitting,
                        decoration: const InputDecoration(labelText: 'Teléfono (10 dígitos)'),
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        validator: RegistrationValidators.phone,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                      const SizedBox(height: 4),
                      AddressAutocompleteField(
                        enabled: !_submitting,
                        onChanged: (value) => _address = value,
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  children: [
                    FilledButton(
                      // RF-01 paso 8: deshabilitado hasta escoger exactamente un rol.
                      onPressed: _role == null || _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Finalizar Registro'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Al continuar aceptas los Términos y la Política de privacidad.',
                      style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
