import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    await ref
        .read(authControllerProvider.notifier)
        .signInWithEmail(_emailController.text, _passwordController.text);

    if (!mounted) return;

    final error = ref.read(authControllerProvider).error;
    if (error != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _signInWithGoogle() async {
    await ref.read(authControllerProvider.notifier).signInWithGoogle();

    if (!mounted) return;

    final error = ref.read(authControllerProvider).error;
    if (error != null && mounted) {
      String message = error.toString();
      if (message.contains('DEVELOPER_ERROR')) {
        message =
            'Google Sign-In failed. Please ensure you have added your SHA-1 fingerprint to the Firebase Console.';
      }
      debugPrint(message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ),
      );
    }
  }

  Future<void> _signInWithApple() async {
    await ref.read(authControllerProvider.notifier).signInWithApple();

    if (!mounted) return;

    final error = ref.read(authControllerProvider).error;
    if (error != null && mounted) {
      String message = error.toString();
      // Handle user cancellation gracefully without showing an error banner
      if (message.contains('1001') ||
          message.contains('canceled') ||
          message.contains('cancelled')) {
        return;
      }
      if (message.contains('1000') ||
          message.contains('AuthorizationError')) {
        message =
            'Sign in with Apple failed. Please ensure Sign in with Apple is enabled in your device settings and Apple Developer account.';
      }
      debugPrint(message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ),
      );
    }
  }

  Future<void> _forgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (context) => _ResetPasswordDialog(
        initialEmail: _emailController.text.trim(),
      ),
    );

    if (email == null || email.isEmpty) return;

    await ref.read(authControllerProvider.notifier).resetPassword(email);

    if (!mounted) return;

    final error = ref.read(authControllerProvider).error;
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent! Check your inbox.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider).isLoading;
    final showAppleSignIn =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        kIsWeb;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  // crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset("assets/na2slna.png", width: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Na2slna',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in to your shared household list',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter your email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      obscureText: _obscurePassword,
                      validator: (value) {
                        if (value == null || value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: isLoading ? null : _forgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: isLoading ? null : _signIn,
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign In'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: isLoading ? null : _signInWithGoogle,
                      icon: const Icon(Icons.g_mobiledata, size: 28),
                      label: const Text('Continue with Google'),
                    ),
                    if (showAppleSignIn) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: isLoading ? null : _signInWithApple,
                        icon: const Icon(Icons.apple, size: 22),
                        label: const Text('Continue with Apple'),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: isLoading
                          ? null
                          : () => Navigator.pushNamed(context, '/register'),
                      child: const Text('Create an account'),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text(
                      "Don't have a shared list yet?",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: isLoading
                          ? null
                          : () => Navigator.pushNamed(context, '/register'),
                      icon: const Icon(Icons.shopping_basket_outlined),
                      label: const Text('Start Shopping'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  final String initialEmail;

  const _ResetPasswordDialog({required this.initialEmail});

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter your email address and we will send you a link to reset your password.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Send Reset Link'),
        ),
      ],
    );
  }
}
