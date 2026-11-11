import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../domain/app_user.dart';

/// Tarjeta de selección de rol del mockup LOGIN (RF-01, paso 7).
class RoleCard extends StatelessWidget {
  const RoleCard({
    super.key,
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final UserRole role;
  final bool selected;
  final VoidCallback? onTap;

  IconData get _icon => switch (role) {
        UserRole.dueno => Icons.pets,
        UserRole.clinica => Icons.medical_services_outlined,
      };

  String get _title => switch (role) {
        UserRole.dueno => 'Dueño de Mascota',
        UserRole.clinica => 'Clínica Veterinaria',
      };

  String get _description => switch (role) {
        UserRole.dueno => 'Agenda citas, guarda su historial y compra productos.',
        UserRole.clinica => 'Gestiona tu agenda, solicitudes e inventario.',
      };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primaryContainer : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.surface : AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_icon, color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _description,
                        style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_circle, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
