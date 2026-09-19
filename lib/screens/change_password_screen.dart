import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/app_theme.dart';
import '../utils/password_policy.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final passwordError = PasswordPolicy.check(_newCtrl.text);
    if (passwordError != null) {
      setState(() {
        _saving = false;
        _error = passwordError;
      });
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() {
        _saving = false;
        _error = 'New passwords don\'t match.';
      });
      return;
    }
    if (_newCtrl.text == _currentCtrl.text) {
      setState(() {
        _saving = false;
        _error = 'That\'s the same as your current password — pick a different one.';
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      setState(() {
        _saving = false;
        _error = 'Could not find your account — try signing out and back in.';
      });
      return;
    }

    try {
      // Firebase requires a recent sign-in for sensitive changes like
      // this one — re-authenticating with the current password proves
      // it's really the account owner making the change, not just
      // someone who found an unlocked phone.
      final credential = EmailAuthProvider.credential(email: email, password: _currentCtrl.text);
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(_newCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Password changed successfully')));
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = switch (e.code) {
          'wrong-password' || 'invalid-credential' => 'Current password is incorrect.',
          'too-many-requests' => 'Too many attempts — please wait a moment and try again.',
          'network-request-failed' => 'No internet connection.',
          'weak-password' => 'That password is too easy to guess — try a stronger one.',
          _ => 'Could not change password: ${e.message ?? e.code}',
        };
      });
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffold,
      appBar: AppBar(title: const Text('Change Password')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _currentCtrl,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'Current password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _newCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'New password',
              helperText:
                  'At least ${PasswordPolicy.minLength} characters — a longer phrase beats a short complex one',
              helperMaxLines: 2,
              prefixIcon: const Icon(Icons.lock_reset),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 20),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscure,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              prefixIcon: Icon(Icons.lock_reset),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
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
                  Expanded(child: Text(_error!, style: const TextStyle(color: AppTheme.danger, fontSize: 12.5))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, size: 18),
            label: Text(_saving ? 'Changing…' : 'Change Password'),
          ),
        ],
      ),
    );
  }
}
