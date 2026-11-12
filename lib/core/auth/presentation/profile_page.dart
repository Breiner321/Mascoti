import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../kernel/plugin_registry.dart';
import '../../router/core_routes.dart';
import '../../theme/app_theme.dart';
import '../auth_providers.dart';
import '../domain/app_user.dart';

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
      await ref.read(authRepositoryProvider).signOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final photo = user.photoUrl;
    final isOwner = user.role == UserRole.dueno;
    final links = ref.watch(pluginRegistryProvider).profileLinksFor(user);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: Semantics(
            image: true,
            label: 'Foto de perfil',
            excludeSemantics: true,
            child: CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.primaryContainer,
              backgroundImage: photo != null ? NetworkImage(photo) : null,
              child: photo == null ? Icon(Icons.person, size: 40, color: AppColors.primary) : null,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Cambio 1: nombre del dueño o nombre comercial de la clínica.
        Text(
          ref.watch(displayNameProvider),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (isOwner && user.telefono != null)
          Text(
            user.telefono!,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        // El correo solo identifica la cuenta de Google con la que entró.
        Text(
          user.email,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        Center(
          child: Chip(
            label: Text(user.role.label),
            backgroundColor: AppColors.primaryContainer,
            side: BorderSide.none,
          ),
        ),
        const SizedBox(height: 24),
        if (isOwner)
          Card(
            child: ListTile(
              leading: Icon(Icons.edit_outlined, color: AppColors.primary),
              title: const Text('Editar perfil'),
              subtitle: const Text('Nombre y teléfono'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(CoreRoutes.editProfile),
            ),
          ),
        Card(
          child: ListTile(
            leading: Icon(Icons.accessibility_new, color: AppColors.primary),
            title: const Text('Accesibilidad'),
            subtitle: const Text('Modo oscuro, contraste y tamaño de texto'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(CoreRoutes.accessibility),
          ),
        ),
        for (final link in links)
          Card(
            child: ListTile(
              leading: Icon(link.icon, color: AppColors.primary),
              title: Text(link.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(link.path),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _confirmSignOut(context, ref),
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}
