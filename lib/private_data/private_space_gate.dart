import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/app/shell/app_shell.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/private_data/private_data_state.dart';

class PrivateSpaceGate extends ConsumerWidget {
  const PrivateSpaceGate({required this.userId, super.key});

  final AppUserId userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(privateBootstrapProvider(userId))
        .when(
          data: (bootstrap) {
            if (bootstrap.isOffline && bootstrap.profile == null) {
              return const _PrivateDataStatusPage(
                icon: Icons.cloud_off_outlined,
                title: 'Private data is unavailable offline',
                message: 'Connect once to prepare this User\'s local cache.',
              );
            }

            return Stack(
              children: [
                const AppShell(),
                if (bootstrap.isOffline)
                  const SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _OfflineBadge(),
                    ),
                  ),
              ],
            );
          },
          error: (error, stackTrace) => const _PrivateDataStatusPage(
            icon: Icons.sync_problem_outlined,
            title: 'Unable to open your private space',
            message: 'Pacta could not load this User\'s private data.',
          ),
          loading: () => const _PrivateDataStatusPage(
            icon: Icons.sync_outlined,
            title: 'Opening your private space',
            message: 'Loading the local cache and checking for updates…',
            showProgress: true,
          ),
        );
  }
}

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 18),
            SizedBox(width: 8),
            Text('Offline · using local cache'),
          ],
        ),
      ),
    );
  }
}

class _PrivateDataStatusPage extends StatelessWidget {
  const _PrivateDataStatusPage({
    required this.icon,
    required this.title,
    required this.message,
    this.showProgress = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 20),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              if (showProgress) ...[
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
