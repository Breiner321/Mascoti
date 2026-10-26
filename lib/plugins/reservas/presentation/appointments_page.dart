import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/auth/domain/app_user.dart';
import 'clinica/clinic_requests_page.dart';
import 'dueno/my_appointments_page.dart';

class AppointmentsPage extends ConsumerWidget {
  const AppointmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProvider)?.role;
    return role == UserRole.clinica ? const ClinicRequestsPage() : const MyAppointmentsPage();
  }
}
