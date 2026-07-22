import 'account_types.dart';

/// Account credentials with plaintext password (in-memory / just decrypted).
class ClearTextAccount {
  final int localId;
  final int schoolID;
  final String username;
  final String password;
  final String schoolName;
  final AccountType? accountType;
  final bool firstLogin;
  final DateTime? lastLogin;
  final DateTime? creationDate;

  const ClearTextAccount({
    required this.localId,
    required this.schoolID,
    required this.username,
    required this.password,
    required this.schoolName,
    this.accountType,
    this.firstLogin = false,
    this.lastLogin,
    this.creationDate,
  });

  ClearTextAccount copyWith({
    int? localId,
    int? schoolID,
    String? username,
    String? password,
    String? schoolName,
    AccountType? accountType,
    bool? firstLogin,
    DateTime? lastLogin,
    DateTime? creationDate,
  }) {
    return ClearTextAccount(
      localId: localId ?? this.localId,
      schoolID: schoolID ?? this.schoolID,
      username: username ?? this.username,
      password: password ?? this.password,
      schoolName: schoolName ?? this.schoolName,
      accountType: accountType ?? this.accountType,
      firstLogin: firstLogin ?? this.firstLogin,
      lastLogin: lastLogin ?? this.lastLogin,
      creationDate: creationDate ?? this.creationDate,
    );
  }
}

/// Account row without password (safe for lists).
class AccountSummary {
  final int localId;
  final int schoolID;
  final String username;
  final String schoolName;
  final AccountType? accountType;
  final DateTime? lastLogin;
  final DateTime creationDate;

  const AccountSummary({
    required this.localId,
    required this.schoolID,
    required this.username,
    required this.schoolName,
    this.accountType,
    this.lastLogin,
    required this.creationDate,
  });
}
