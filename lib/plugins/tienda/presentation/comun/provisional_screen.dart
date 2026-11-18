import 'package:flutter/material.dart';

import '../../../../core/widgets/module_placeholder.dart';

/// Pantalla PROVISIONAL de la tienda (semana 6, Dev A): solo deja las rutas
/// listas. La reemplazan el Dev B (inventario y pedidos de la clínica) y el
/// Dev C (tienda, carrito y pedidos del dueño) usando `ShopRepository`.
///
/// Con [fullScreen] (rutas fuera de la barra inferior) lleva su propio
/// `Scaffold` con botón de volver.
class ProvisionalScreen extends StatelessWidget {
  const ProvisionalScreen({
    super.key,
    required this.title,
    required this.description,
    required this.requirement,
    this.fullScreen = false,
  });

  final String title;
  final String description;
  final String requirement;
  final bool fullScreen;

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      child: ModulePlaceholder(
        title: title,
        description: description,
        requirements: [requirement],
      ),
    );
    if (!fullScreen) return Center(child: body);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: Center(child: body)),
    );
  }
}
