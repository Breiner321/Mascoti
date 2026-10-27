import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_theme.dart';
import '../auth_providers.dart';
import '../domain/app_user.dart';
import 'widgets/owner_profile_form.dart';

/// "Editar perfil" del dueño (Cambio 1): nombre completo y teléfono. Las
/// citas ya creadas conservan el nombre que tenían (copia histórica).
class EditProfilePage extends ConsumerWidget {
  const EditProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null || user.role != UserRole.dueno) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Editar perfil',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
        ),
        const SizedBox(height: 24),
        OwnerProfileForm(
          initialName: user.nombre ?? '',
          initialPhone: user.telefono ?? '',
          submitLabel: 'Guardar cambios',
          onSaved: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Perfil actualizado')),
            );
            if (context.canPop()) context.pop();
          },
        ),
      ],
    );
  }
}
