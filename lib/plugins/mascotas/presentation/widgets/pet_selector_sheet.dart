import 'package:flutter/material.dart';

import '../../../../core/domain/pet.dart';
import '../../../../core/theme/app_theme.dart';
import 'pet_avatar.dart';

/// Hoja inferior para cambiar la mascota activa del home.
class PetSelectorSheet extends StatelessWidget {
  const PetSelectorSheet({
    super.key,
    required this.pets,
    required this.selectedId,
    required this.onSelect,
    this.onAddPet,
  });

  final List<Pet> pets;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback? onAddPet;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Mis mascotas', style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final pet in pets)
            ListTile(
              leading: PetAvatar(name: pet.nombre, photoPath: pet.fotoPath, size: 40),
              title: Text(pet.nombre),
              subtitle: Text(pet.summary(now)),
              trailing: pet.id == selectedId
                  ? Icon(Icons.check_circle, color: AppColors.primary)
                  : null,
              onTap: () {
                Navigator.pop(context);
                onSelect(pet.id);
              },
            ),
          if (onAddPet != null)
            ListTile(
              leading: Icon(Icons.add_circle_outline, color: AppColors.primary),
              title: const Text('Agregar mascota'),
              onTap: () {
                Navigator.pop(context);
                onAddPet!();
              },
            ),
        ],
      ),
    );
  }
}
