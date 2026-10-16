import 'package:flutter/material.dart';

import '../../../core/domain/clinic_service.dart';
import '../../../core/theme/app_theme.dart';
import 'service_validators.dart';

/// Tarjeta de un servicio del catálogo (RF-05). Tocarla edita; deslizarla o
/// tocar la papelera elimina (tras [confirmDelete]).
class ServiceCard extends StatelessWidget {
  const ServiceCard({
    super.key,
    required this.service,
    required this.onTap,
    required this.confirmDelete,
    required this.onDeleted,
  });

  final ClinicService service;
  final VoidCallback onTap;

  /// Pide confirmación y hace el borrado lógico; true si se eliminó.
  final Future<bool> Function() confirmDelete;

  /// La tarjeta ya salió de la lista (tras deslizarla).
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey('service-${service.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirmDelete(),
      onDismissed: (_) => onDeleted(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: colorScheme.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(Icons.delete_outline, color: colorScheme.onError),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service.nombre, style: textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(
                            label: Text(service.categoria.label),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: AppColors.primaryContainer,
                            side: BorderSide.none,
                          ),
                          Text(
                            '${service.duracionMin} min',
                            style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                      if (service.descripcion.isNotEmpty)
                        Text(
                          service.descripcion,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                        ),
                    ],
                  ),
                ),
                Text(
                  formatCop(service.precio),
                  style: textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: confirmDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
