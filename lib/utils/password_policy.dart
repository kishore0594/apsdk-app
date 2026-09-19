/// Password strength policy shared by Sign Up and Change Password —
/// deliberately one canonical check rather than two separate copies, so
/// the rule can't quietly drift between screens the way an earlier bug
/// let two "collected this week" calculations disagree with each other.
///
/// Length-first, matching current NIST guidance (SP 800-63-4) rather
/// than older "must have a symbol and a number" rules — those rules are
/// now considered counterproductive, since they push people toward
/// predictable patterns like "Password123!" instead of genuinely
/// stronger passwords. What actually matters most is length, plus
/// ruling out passwords so common they're the first thing anyone
/// (or any script) would try.
class PasswordPolicy {
  static const minLength = 12;

  static const _commonWeakPasswords = {
    'password', 'password1', 'password123', 'passwordpassword',
    '12345678', '123456789', '1234567890', 'qwertyuiop', 'qwerty123',
    'letmein123', 'welcome123', 'admin1234', 'iloveyou1', 'football1',
    'sunshine1', 'princess1', 'abcd1234', 'abcdefgh', '11111111',
    '00000000', 'changeme1', 'trustno1',
  };

  /// Returns an error message if the password doesn't meet the policy,
  /// or null if it's fine.
  static String? check(String password) {
    if (password.length < minLength) {
      return 'Password needs to be at least $minLength characters — length matters '
          'more than mixing in symbols, so a longer plain phrase is genuinely stronger.';
    }
    if (_commonWeakPasswords.contains(password.toLowerCase())) {
      return 'That password is too common to be safe — please choose something '
          'less predictable.';
    }
    return null;
  }
}
