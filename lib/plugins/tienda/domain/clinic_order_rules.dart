import 'package:flutter/foundation.dart';

import '../../../core/domain/order.dart';

/// Pestañas de "Pedidos recibidos" de la clínica (RF-07).
enum ClinicOrderTab {
  porPreparar('Por preparar', {OrderStatus.pagado, OrderStatus.preparando}),
  listos('Listos o enviados', {OrderStatus.listo, OrderStatus.enviado}),
  historial('Historial', {OrderStatus.entregado, OrderStatus.cancelado});

  const ClinicOrderTab(this.label, this.statuses);

  final String label;
  final Set<OrderStatus> statuses;

  /// Pedidos de [orders] que van en esta pestaña (mismo orden).
  List<ShopOrder> select(List<ShopOrder> orders) => [
        for (final o in orders)
          if (statuses.contains(o.estado)) o
      ];
}

/// Botón del siguiente paso de un pedido: texto y estado al que pasa.
@immutable
class OrderAction {
  const OrderAction(this.label, this.to);

  final String label;
  final OrderStatus to;

  @override
  bool operator ==(Object other) => other is OrderAction && other.label == label && other.to == to;

  @override
  int get hashCode => Object.hash(label, to);

  @override
  String toString() => 'OrderAction($label → ${to.value})';
}

/// Reglas de los pedidos recibidos que no dependen de la UI. Siguen la
/// máquina de estados de [OrderStatus]; el cambio real lo hace la Edge
/// Function `actualizar-pedido`.
abstract final class ClinicOrderRules {
  static const _labels = {
    OrderStatus.preparando: 'Empezar a preparar',
    OrderStatus.listo: 'Listo para recoger',
    OrderStatus.enviado: 'Marcar como enviado',
    OrderStatus.entregado: 'Entregado',
  };

  /// Siguiente paso de [order] (sin contar cancelar), o null si ya no
  /// avanza (entregado o cancelado).
  static OrderAction? nextAction(ShopOrder order) {
    final next = order.estado.nextStates(order.entrega.tipo);
    for (final to in _labels.keys) {
      if (next.contains(to)) return OrderAction(_labels[to]!, to);
    }
    return null;
  }

  /// La clínica puede cancelar (pagado o en preparación).
  static bool canCancel(ShopOrder order) =>
      order.estado.canTransitionTo(OrderStatus.cancelado, order.entrega.tipo);

  /// Motivo de cancelación válido: obligatorio y de máximo 300 caracteres.
  static String? validateReason(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Indica el motivo de la cancelación';
    if (v.length > OrderLimits.maxMotivo) {
      return 'El motivo no puede superar ${OrderLimits.maxMotivo} caracteres';
    }
    return null;
  }
}
