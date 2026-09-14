import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/app_theme.dart';
import '../utils/app_logo.dart';
import '../utils/locale_controller.dart';
import '../utils/app_strings.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      // On success, the auth-state listener in main.dart takes over and
      // shows the app — nothing else to do here.
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = switch (e.code) {
          'user-not-found' || 'invalid-credential' => 'No account found with that email.',
          'wrong-password' || 'invalid-login-credentials' => 'Incorrect password.',
          'invalid-email' => 'That doesn\'t look like a valid email address.',
          'too-many-requests' => 'Too many attempts — please wait a moment and try again.',
          'network-request-failed' => 'No internet connection.',
          _ => 'Sign-in failed: ${e.message ?? e.code}',
        };
      });
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.primary, AppTheme.primaryDark],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6)),
                        ],
                      ),
                      child: const AppLogo(size: 84),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      AppStrings.t('app_name'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 23, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      AppStrings.t('store_management'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.8)),
                    ),
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: _pickLanguage,
                      icon: const Icon(Icons.language, size: 16, color: Colors.white),
                      label: Text(
                        LocaleController.instance.isTamil ? 'தமிழ் ▾' : 'English ▾',
                        style: const TextStyle(color: Colors.white, fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(AppStrings.t('sign_in'),
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: AppStrings.t('email'),
                              prefixIcon: const Icon(Icons.email_outlined),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            onSubmitted: (_) => _signIn(),
                            decoration: InputDecoration(
                              labelText: AppStrings.t('password'),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                                    size: 20),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.danger.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, size: 16, color: AppTheme.danger),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_error!,
                                        style: const TextStyle(
                                            color: AppTheme.danger, fontSize: 12.5)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: _loading ? null : _signIn,
                            icon: _loading
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.login, size: 18),
                            label: Text(_loading ? AppStrings.t('signing_in') : AppStrings.t('sign_in')),
                          ),
                        ],
                      ),
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

  Future<void> _pickLanguage() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.t('select_language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(AppStrings.t('english')),
              trailing: LocaleController.instance.language == 'en'
                  ? const Icon(Icons.check, color: AppTheme.primary)
                  : null,
              onTap: () => Navigator.pop(context, 'en'),
            ),
            ListTile(
              title: Text(AppStrings.t('tamil')),
              trailing: LocaleController.instance.language == 'ta'
                  ? const Icon(Icons.check, color: AppTheme.primary)
                  : null,
              onTap: () => Navigator.pop(context, 'ta'),
            ),
          ],
        ),
      ),
    );
    if (choice != null) {
      await LocaleController.instance.setLanguage(choice);
      if (mounted) setState(() {});
    }
  }
}
