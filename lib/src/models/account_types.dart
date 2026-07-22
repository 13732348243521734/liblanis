enum AccountType { student, teacher, parent }

extension AccountTypeX on AccountType {
  String get name => toString().split('.').last;

  static AccountType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'student':
        return AccountType.student;
      case 'teacher':
        return AccountType.teacher;
      case 'parent':
        return AccountType.parent;
      default:
        return AccountType.student;
    }
  }
}
