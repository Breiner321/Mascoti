// ÚNICO archivo del core que conoce los plugins.
// Para activar/desactivar un módulo completo, agrégalo o coméntalo aquí.

import '../../plugins/clinica/clinica_plugin.dart';
import '../../plugins/mascotas/mascotas_plugin.dart';
import '../../plugins/reservas/reservas_plugin.dart';
import 'mascoti_plugin.dart';

final List<MascotiPlugin> enabledPlugins = [
  const MascotasPlugin(), // Dueño: home, mascotas, historial (RF-08)
  const ClinicaPlugin(), // Clínica: perfil, servicios, agenda (RF-04..06)
  const ReservasPlugin(), // Ambos: citas (RF-14)
  // const DirectorioPlugin(), // semana 3 — RF-09
  // const ChatPlugin(),       // semana 5 — RF-15, RF-16
  // const TiendaPlugin(),     // semana 6 — RF-07, RF-12
  // const SosPlugin(),        // semana 7 — RF-10
  // const UtilidadesPlugin(), // semana 7 — RF-17, RF-18
  // const ChatbotPlugin(),    // semana 7 — RF-11 (opcional)
];
