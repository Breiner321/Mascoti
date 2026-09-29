import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../auth_providers.dart';
import '../domain/app_user.dart';
import '../domain/registration.dart';
import '../domain/session_state.dart';

/// RF-01: selección de rol y, si es Clínica, datos del negocio.
///
/// Pendiente de la semana 1 (RF-01):
/// - Autocompletado de dirección con Google Places (lat/lng obligatorios).
/// - Onboarding de 3 pasos para el dueño tras registrarse.
class RegistrationPage extends ConsumerStatefulWidget {
  const RegistrationPage({super.key});

  @override
  ConsumerState<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends ConsumerState<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();

  UserRole? _role;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final role = _role;
    if (role == null) return;
    if (role == UserRole.clinica && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final request = role == UserRole.dueno
        ? const RegistrationRequest.owner()
        : RegistrationRequest.clinic(
            ClinicRegistration(
              nombre: _name.text,
              telefono: _phone.text,
              direccion: _address.text,
            ),
          );

    setState(() => _submitting = true);
    try {
      await ref.read(authRepositoryProvider).completeRegistration(request);
      // Al crearse users/{uid}, sessionProvider cambia y el router redirige.
    } on FirebaseFunctionsException catch (e) {
      switch (e.code) {
        case 'already-exists':
          _showMessage('Esta cuenta ya está registrada. Iniciando sesión...');
        case 'deadline-exceeded' || 'unavailable':
          _showMessage(
            'No se pudo completar el registro. Verifica tu conexión',
            retry: true,
          );
        default:
          _showMessage(e.message ?? 'No se pudo completar el registro', retry: true);
      }
    } catch (_) {
      _showMessage('No se pudo completar el registro. Verifica tu conexión', retry: true);
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final email = session is NeedsRegistration ? session.email : '';
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear cuenta'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('Usar otra cuenta'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (email.isNotEmpty)
                Text(email, style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
              const SizedBox(height: 8),
              Text(
                '¿Cómo usarás Mascoti?',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                role: UserRole.dueno,
                icon: Icons.pets,
                description: 'Agenda citas, guarda su historial y compra productos.',
                selected: _role == UserRole.dueno,
                onTap: () => setState(() => _role = UserRole.dueno),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                role: UserRole.clinica,
                icon: Icons.local_hospital_outlined,
                description: 'Controla tu agenda, solicitudes e inventario.',
                selected: _role == UserRole.clinica,
                onTap: () => setState(() => _role = UserRole.clinica),
              ),
              if (_role == UserRole.clinica) ...[
                const SizedBox(height: 24),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nombre comercial'),
                  textCapitalization: TextCapitalization.words,
                  validator: RegistrationValidators.clinicName,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: 'Teléfono (10 dígitos)'),
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  validator: RegistrationValidators.phone,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: 12),
                // TODO(RF-01): reemplazar por autocompletado de Google Places.
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Dirección'),
                  validator: RegistrationValidators.address,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
              ],
              const SizedBox(height: 32),
              FilledButton(
                // RF-01 paso 8: deshabilitado hasta escoger exactamente un rol.
                onPressed: _role == null || _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Finalizar Registro'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.icon,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final UserRole role;
  final IconData icon;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryContainer : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? AppColors.primary : Colors.black12,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role == UserRole.dueno ? 'Soy Dueño de Mascota' : 'Soy Clínica Veterinaria',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(description, style: const TextStyle(color: AppColors.textMuted)),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
