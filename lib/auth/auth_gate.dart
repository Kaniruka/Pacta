import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/app/status_page.dart';
import 'package:pacta/auth/auth_state.dart';
import 'package:pacta/private_data/private_space_gate.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(authenticatedUserProvider)
        .when(
          data: (userId) => userId == null
              ? const _SignInPage()
              : PrivateSpaceGate(userId: userId),
          error: (error, stackTrace) => const StatusPage(
            icon: Icons.cloud_off_outlined,
            title: 'Unable to check your session',
            message: 'Check your connection and reopen Pacta.',
          ),
          loading: () => const StatusPage(
            icon: Icons.lock_outline,
            title: 'Opening your private space',
            message: 'Restoring the authenticated session…',
            showProgress: true,
          ),
        );
  }
}

class _SignInPage extends ConsumerStatefulWidget {
  const _SignInPage();

  @override
  ConsumerState<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<_SignInPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      await ref
          .read(authSessionProvider)
          .signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Sign-in failed. Check your invitation and details.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_outline, size: 56),
                  const SizedBox(height: 24),
                  Text(
                    'Sign in to Pacta',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your Tasks and focus history stay private to your User.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: _submitting ? null : (_) => _signIn(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error case final error?) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _submitting ? null : _signIn,
                    child: Text(_submitting ? 'Signing in…' : 'Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
