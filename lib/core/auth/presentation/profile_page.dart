import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../auth_providers.dart';

/// Perfil del usuario y cierre de sesión (RF-03).
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      // TODO(RF-13): borrar el token FCM de users/{uid}/devices antes de salir.
      await ref.read(authRepositoryProvider).signOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final photo = user.photoUrl;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.primaryContainer,
            backgroundImage: photo != null ? NetworkImage(photo) : null,
            child: photo == null
                ? const Icon(Icons.person, size: 40, color: AppColors.primary)
                : null,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          user.displayName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          user.email,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        Center(
          child: Chip(
            label: Text(user.role.label),
            backgroundColor: AppColors.primaryContainer,
            side: BorderSide.none,
          ),
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: () => _confirmSignOut(context, ref),
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}
