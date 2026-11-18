import 'dart:math' as math;

import '../../../core/domain/product.dart';

/// Reglas del inventario de la clínica (RF-07) que no dependen de la UI.
abstract final class InventoryRules {
  /// Con esta cantidad o menos (y más de 0) se avisa "stock bajo".
  static const lowStockThreshold = 3;

  /// Coincidencia a partir de la cual se advierte "producto duplicado".
  static const duplicateSimilarity = 0.85;

  /// Stock bajo: quedan entre 1 y [lowStockThreshold] unidades de un
  /// producto publicado. Un producto agotado o inactivo no cuenta.
  static bool isLowStock(Product product) =>
      product.estado != ProductStatus.inactivo &&
      product.stock > 0 &&
      product.stock <= lowStockThreshold;

  /// Estado que queda después de cambiar el stock a [stock]: `agotado` solo
  /// con 0 y `activo` al reponer; un producto inactivo sigue inactivo.
  static ProductStatus statusAfterStock(ProductStatus current, int stock) =>
      current == ProductStatus.inactivo ? ProductStatus.inactivo : ProductStatus.forStock(stock);

  /// Productos que pasan [filter] y cuyo nombre contiene [query] (sin
  /// distinguir mayúsculas ni tildes).
  static List<Product> filter(
    List<Product> products, {
    String query = '',
    InventoryFilter filter = InventoryFilter.todos,
  }) {
    final q = normalize(query);
    return [
      for (final p in products)
        if (filter.matches(p) && (q.isEmpty || normalize(p.nombre).contains(q))) p,
    ];
  }

  /// Producto de [inventory] con un nombre muy parecido a [nombre] (más de
  /// 85 % de coincidencia), sin contar [excludeId]. null si no hay.
  static Product? similarProduct(String nombre, List<Product> inventory, {String? excludeId}) {
    Product? best;
    var bestScore = 0.0;
    for (final p in inventory) {
      if (p.id == excludeId) continue;
      final score = nameSimilarity(nombre, p.nombre);
      if (score > duplicateSimilarity && score > bestScore) {
        best = p;
        bestScore = score;
      }
    }
    return best;
  }

  /// Coincidencia entre 0 y 1 de dos nombres (1 − distancia de Levenshtein
  /// / largo del más largo), sin mayúsculas, tildes ni espacios repetidos.
  static double nameSimilarity(String a, String b) {
    final x = normalize(a);
    final y = normalize(b);
    if (x.isEmpty && y.isEmpty) return 1;
    final longest = math.max(x.length, y.length);
    return 1 - _levenshtein(x, y) / longest;
  }

  /// Minúsculas, sin tildes y con un solo espacio entre palabras.
  static String normalize(String value) {
    const from = 'áéíóúüñ';
    const to = 'aeiouun';
    final lower = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final buffer = StringBuffer();
    for (final char in lower.split('')) {
      final i = from.indexOf(char);
      buffer.write(i < 0 ? char : to[i]);
    }
    return buffer.toString();
  }

  static int _levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = math.min(
          math.min(current[j - 1] + 1, previous[j] + 1),
          previous[j - 1] + cost,
        );
      }
      previous = current;
    }
    return previous[b.length];
  }
}

/// Filtro de la lista del inventario.
enum InventoryFilter {
  todos('Todos'),
  activo('Activos'),
  agotado('Agotados'),
  inactivo('Inactivos'),
  stockBajo('Stock bajo');

  const InventoryFilter(this.label);

  final String label;

  bool matches(Product p) => switch (this) {
        todos => true,
        activo => p.estado == ProductStatus.activo,
        agotado => p.estado == ProductStatus.agotado,
        inactivo => p.estado == ProductStatus.inactivo,
        stockBajo => InventoryRules.isLowStock(p),
      };
}
