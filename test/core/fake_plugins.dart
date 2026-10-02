import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mascoti/core/auth/domain/app_user.dart';
import 'package:mascoti/core/kernel/mascoti_plugin.dart';

class FakePlugin extends MascotiPlugin {
  FakePlugin(
    this.id, {
    required this.roles,
    List<String>? paths,
    this.tabs = const [],
  }) : paths = paths ?? ['/$id'];

  @override
  final String id;

  @override
  final Set<UserRole> roles;

  final List<String> paths;
  final List<PluginDestination> tabs;

  @override
  List<RouteBase> routes() => [
        for (final p in paths)
          GoRoute(path: p, builder: (context, state) => const SizedBox()),
      ];

  @override
  List<PluginDestination> destinations(UserRole role) =>
      roles.contains(role) ? tabs : const [];
}

PluginDestination tab(String path, int order) =>
    PluginDestination(label: path, icon: Icons.circle, path: path, order: order);
