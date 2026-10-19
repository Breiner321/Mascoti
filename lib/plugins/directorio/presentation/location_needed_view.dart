import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/places/google_places_service.dart';
import '../../../core/places/places_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/address_autocomplete_field.dart';
import 'directory_providers.dart';

/// Sin ubicación del GPS (RF-09, flujo alterno): mensaje explicativo y
/// búsqueda por dirección o ciudad con autocompletado de Google Places.
class LocationNeededView extends ConsumerWidget {
  const LocationNeededView({
    super.key,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        const Icon(Icons.location_off_outlined,
            size: 48, color: AppColors.primary),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: textTheme.bodyLarge),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.my_location),
            label: Text(actionLabel),
          ),
        ),
        const SizedBox(height: 24),
        Text('O busca por dirección o ciudad',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        AddressAutocompleteField(
          label: 'Dirección o ciudad',
          service: ref.watch(placesSearchServiceProvider),
          attribution: Env.hasGooglePlaces
              ? GooglePlacesService.attribution
              : AddressAutocompleteField.osmAttribution,
          onChanged: (place) {
            if (place != null) {
              ref.read(manualCenterProvider.notifier).set(place);
            }
          },
        ),
      ],
    );
  }
}
