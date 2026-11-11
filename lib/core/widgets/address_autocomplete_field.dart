import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../places/address_search_service.dart';
import '../places/place_address.dart';
import '../places/places_providers.dart';
import '../theme/app_theme.dart';

/// Campo de dirección con autocompletado de OpenStreetMap (RF-01, pasos 9-10).
///
/// Solo es válido si la dirección se escoge de la lista y tiene coordenadas:
/// el texto libre o un lugar sin lat/lng muestran
/// "Selecciona una dirección válida de la lista" y bloquean el formulario.
class AddressAutocompleteField extends ConsumerStatefulWidget {
  const AddressAutocompleteField({
    super.key,
    this.label = 'Dirección',
    this.onChanged,
    this.enabled = true,
  });

  final String label;
  final ValueChanged<PlaceAddress?>? onChanged;
  final bool enabled;

  static const invalidMessage = 'Selecciona una dirección válida de la lista';
  static const debounce = Duration(milliseconds: 400);

  @override
  ConsumerState<AddressAutocompleteField> createState() =>
      _AddressAutocompleteFieldState();
}

enum _Status { idle, searching, results, empty, error, resolving }

class _AddressAutocompleteFieldState
    extends ConsumerState<AddressAutocompleteField> {
  final _fieldKey = GlobalKey<FormFieldState<PlaceAddress>>();
  final _controller = TextEditingController();
  Timer? _debounce;

  _Status _status = _Status.idle;
  List<AddressSuggestion> _suggestions = const [];
  String? _errorMessage;

  /// Una sesión de facturación de Places por dirección escogida.
  bool _newSession = true;

  /// Evita mostrar resultados de una búsqueda vieja.
  int _searchId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  AddressSearchService get _service => ref.read(addressSearchServiceProvider);

  void _onTextChanged(String text) {
    // Editar el texto invalida la dirección escogida antes.
    if (_fieldKey.currentState?.value != null) _setValue(null);

    _debounce?.cancel();
    if (text.trim().length < 3) {
      setState(() {
        _status = _Status.idle;
        _suggestions = const [];
      });
      return;
    }
    _debounce = Timer(AddressAutocompleteField.debounce, () => _search(text));
  }

  Future<void> _search(String text) async {
    final id = ++_searchId;
    setState(() => _status = _Status.searching);
    try {
      final results = await _service.suggest(text, newSession: _newSession);
      _newSession = false;
      if (!mounted || id != _searchId) return;
      setState(() {
        _suggestions = results;
        _status = results.isEmpty ? _Status.empty : _Status.results;
      });
    } on AddressSearchUnavailable {
      _showError('El buscador de direcciones no está disponible. Intenta en un momento');
    } catch (_) {
      if (id == _searchId) {
        _showError('No se pudieron cargar las direcciones. Verifica tu conexión');
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _status = _Status.error;
      _errorMessage = message;
      _suggestions = const [];
    });
  }

  Future<void> _select(AddressSuggestion suggestion) async {
    _debounce?.cancel();
    _searchId++;
    setState(() {
      _status = _Status.resolving;
      _suggestions = const [];
    });
    _controller.text = suggestion.fullText;

    PlaceAddress? address;
    try {
      address = await _service.resolve(suggestion);
    } catch (_) {
      address = null;
    }
    if (!mounted) return;
    _newSession = true;
    setState(() => _status = _Status.idle);
    _setValue(address);
    // Sin coordenadas: se marca en rojo de inmediato (RF-01, flujo alterno).
    if (address == null) _fieldKey.currentState?.validate();
  }

  void _setValue(PlaceAddress? value) {
    _fieldKey.currentState?.didChange(value);
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return FormField<PlaceAddress>(
      key: _fieldKey,
      validator: (value) =>
          value == null ? AddressAutocompleteField.invalidMessage : null,
      builder: (field) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            enabled: widget.enabled,
            onChanged: _onTextChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: 'Busca y escoge tu dirección',
              prefixIcon: const Icon(Icons.location_on_outlined),
              suffixIcon: field.value != null
                  ? Icon(Icons.check_circle, color: AppColors.success)
                  : null,
              errorText: field.errorText,
            ),
          ),
          _buildStatus(),
        ],
      ),
    );
  }

  Widget _buildStatus() {
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: AppColors.textMuted);
    switch (_status) {
      case _Status.idle:
        return const SizedBox.shrink();
      case _Status.searching:
      case _Status.resolving:
        return const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(),
        );
      case _Status.empty:
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Text('No encontramos esa dirección. Revisa cómo la escribiste.',
              style: muted),
        );
      case _Status.error:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(child: Text(_errorMessage ?? '', style: muted)),
              TextButton(
                onPressed: () => _search(_controller.text),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        );
      case _Status.results:
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Material(
            color: AppColors.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (final s in _suggestions)
                  ListTile(
                    leading: Icon(Icons.place_outlined,
                        color: AppColors.primary),
                    title: Text(s.primaryText),
                    subtitle:
                        s.secondaryText.isEmpty ? null : Text(s.secondaryText),
                    onTap: () => _select(s),
                  ),
                // Atribución exigida por la licencia de los datos (ODbL).
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Datos © colaboradores de OpenStreetMap',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }
}
