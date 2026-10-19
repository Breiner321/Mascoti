import 'package:flutter/material.dart';

/// Fecha corta con año para la UI: "sáb, 16 nov 2020".
/// `formatMediumDate` sola no incluye el año, y en el historial y la fecha
/// de nacimiento el año es lo más importante.
String dateLabel(BuildContext context, DateTime date) {
  final l = MaterialLocalizations.of(context);
  return '${l.formatMediumDate(date)} ${l.formatYear(date)}';
}
