import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Círculo con las iniciales del otro participante (clínicas y dueños no
/// tienen foto en el modelo). Decorativo: el nombre ya se lee al lado.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, required this.name, this.size = 44});

  final String name;
  final double size;

  /// "Clínica Patitas" → "CP"; "Ana" → "A".
  static String initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final letters = words.take(2).map((w) => w.characters.first.toUpperCase());
    return letters.join();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle),
        child: Text(
          initials(name),
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.36,
          ),
        ),
      ),
    );
  }
}
