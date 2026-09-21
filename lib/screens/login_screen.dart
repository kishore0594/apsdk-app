import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../db/db_helper.dart';
import '../utils/app_theme.dart';
import '../utils/app_logo.dart';
import '../utils/app_info.dart';
import '../utils/password_policy.dart';
import '../utils/locale_controller.dart';
import '../utils/app_strings.dart';
import '../utils/session_lock.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _accessCodeCtrl = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final remembered = SessionLock.instance.rememberedEmail;
    if (remembered != null) _emailCtrl.text = remembered;
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final lock = SessionLock.instance;
    final current = FirebaseAuth.instance.currentUser;
    final sameAccount = current != null && (current.email ?? '').toLowerCase() == email.toLowerCase();
    try {
      // OFFLINE PATH: this phone already holds a live session for this
      // account (the user only locked it via Logout). Verify the
      // password against the fingerprint stored on the device — no
      // internet involved at all.
      if (sameAccount && lock.matches(email, password)) {
        await lock.unlock();
        return;
      }
      if (sameAccount && lock.knows(email)) {
        // Right account, but the password doesn't match what's stored.
        // It may have been changed on another phone — confirm with the
        // server if we're online; offline this correctly fails below.
        await current!.reauthenticateWithCredential(
            EmailAuthProvider.credential(email: email, password: password));
        await lock.rememberCredentials(email, password);
        await lock.unlock();
        return;
      }
      // ONLINE PATH: first sign-in on this phone, or switching accounts.
      // Deliberately no signOut() first — if this fails offline, the
      // existing session is left untouched rather than lost.
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      await lock.rememberCredentials(email, password);
      await lock.unlock();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'network-request-failed') {
        setState(() => _error = sameAccount
            ? (lock.knows(email)
                ? 'Incorrect password.'
                : 'Offline sign-in isn\'t set up on this phone yet — connect to internet and sign in once.')
            : (current != null
                ? 'Switching to a different account needs internet. Use ${current.email} to sign in offline.'
                : 'First sign-in on this phone needs internet. After that, you can sign in offline.'));
        return;
      }
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

  Future<void> _signUp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Everything below is checked before touching Firebase, so a mistake
    // here never costs a network round-trip.
    if (_accessCodeCtrl.text.trim() != AppInfo.signupAccessCode) {
      setState(() {
        _loading = false;
        _error = 'That access code isn\'t right — ask whoever manages the store for it.';
      });
      return;
    }
    final passwordError = PasswordPolicy.check(_passwordCtrl.text);
    if (passwordError != null) {
      setState(() {
        _loading = false;
        _error = passwordError;
      });
      return;
    }
    if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
      setState(() {
        _loading = false;
        _error = 'Passwords don\'t match.';
      });
      return;
    }
    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      final uid = credential.user?.uid;
      if (uid != null) {
        // Defaults every new account to view-only — an admin upgrades
        // someone deliberately via Manage Users, never by accident.
        await DBHelper.instance.createUserRoleDoc(uid, _emailCtrl.text.trim());
      }
      await SessionLock.instance.rememberCredentials(_emailCtrl.text.trim(), _passwordCtrl.text);
      await SessionLock.instance.unlock();
      // On success, same as sign-in — main.dart's auth listener takes it
      // from here.
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = switch (e.code) {
          'email-already-in-use' => 'An account already exists with that email — try signing in instead.',
          'invalid-email' => 'That doesn\'t look like a valid email address.',
          'weak-password' => 'That password is too easy to guess — try a stronger one.',
          'network-request-failed' => 'No internet connection.',
          _ => 'Could not create account: ${e.message ?? e.code}',
        };
      });
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _error = null;
      _confirmPasswordCtrl.clear();
      _accessCodeCtrl.clear();
    });
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
                          Text(_isSignUp ? 'Create Account' : AppStrings.t('sign_in'),
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
                            onSubmitted: (_) => _isSignUp ? _signUp() : _signIn(),
                            decoration: InputDecoration(
                              labelText: AppStrings.t('password'),
                              helperText: _isSignUp ? 'At least 12 characters — a longer phrase beats a short complex one' : null,
                              helperMaxLines: 2,
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                                    size: 20),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                          if (_isSignUp) ...[
                            const SizedBox(height: 14),
                            TextField(
                              controller: _confirmPasswordCtrl,
                              obscureText: _obscure,
                              decoration: const InputDecoration(
                                labelText: 'Confirm password',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _accessCodeCtrl,
                              onSubmitted: (_) => _signUp(),
                              decoration: const InputDecoration(
                                labelText: 'Access code',
                                helperText: 'Ask whoever manages the store for this',
                                helperMaxLines: 2,
                                prefixIcon: Icon(Icons.vpn_key_outlined),
                              ),
                            ),
                          ],
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
                            onPressed: _loading ? null : (_isSignUp ? _signUp : _signIn),
                            icon: _loading
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : Icon(_isSignUp ? Icons.person_add_alt : Icons.login, size: 18),
                            label: Text(_loading
                                ? (_isSignUp ? 'Creating account…' : AppStrings.t('signing_in'))
                                : (_isSignUp ? 'Create Account' : AppStrings.t('sign_in'))),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _loading ? null : _toggleMode,
                            child: Text(
                              _isSignUp
                                  ? 'Already have an account? Sign In'
                                  : 'Don\'t have an account? Sign Up',
                              style: const TextStyle(fontSize: 13),
                            ),
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
