import 'package:flutter/foundation.dart';

import '../../../core/domain/order.dart';

/// Línea de tiempo del pedido del dueño (RF-12):
/// pagado → preparando → listo (recoger) o enviado (domicilio) → entregado.

enum TimelineStepState { done, current, pending }

@immutable
class TimelineStep {
  const TimelineStep(
      {required this.status, required this.label, required this.state});

  final OrderStatus status;
  final String label;
  final TimelineStepState state;

  @override
  bool operator ==(Object other) =>
      other is TimelineStep && other.status == status && other.state == state;

  @override
  int get hashCode => Object.hash(status, state);

  @override
  String toString() => '${status.value}:${state.name}';
}

/// Pasos del pedido según su entrega. Vacío si no está en ese camino
/// (pendiente de pago, rechazado, expirado o cancelado: la pantalla muestra
/// su aviso).
List<TimelineStep> orderTimeline(ShopOrder order) {
  final steps = [
    (OrderStatus.pagado, 'Pagado'),
    (OrderStatus.preparando, 'En preparación'),
    order.entrega.tipo == DeliveryType.domicilio
        ? (OrderStatus.enviado, 'Enviado')
        : (OrderStatus.listo, 'Listo para recoger'),
    (OrderStatus.entregado, 'Entregado'),
  ];
  final index = steps.indexWhere((s) => s.$1 == order.estado);
  if (index < 0) return const [];
  final finished = order.estado == OrderStatus.entregado;
  return [
    for (var i = 0; i < steps.length; i++)
      TimelineStep(
        status: steps[i].$1,
        label: steps[i].$2,
        state: i < index || (i == index && finished)
            ? TimelineStepState.done
            : i == index
                ? TimelineStepState.current
                : TimelineStepState.pending,
      ),
  ];
}
