class Medication {
  Medication({
    required this.id,
    required this.seniorId,
    required this.name,
    required this.strength,
    required this.dosageForm,
    this.quantity,
    this.purpose,
    this.prescribedInstructions,
    this.barcode,
    this.appearance,
    this.isActive = true,
  });

  factory Medication.fromJson(Map<String, dynamic> j) => Medication(
        id: j['id'],
        seniorId: j['senior_id'],
        name: j['name'],
        strength: j['strength'],
        dosageForm: j['dosage_form'],
        quantity: j['quantity'],
        purpose: j['purpose'],
        prescribedInstructions: j['prescribed_instructions'],
        barcode: j['barcode'],
        appearance: j['appearance'],
        isActive: j['is_active'] ?? true,
      );

  final String id;
  final String seniorId;
  final String name;
  final String strength;
  final String dosageForm;
  final String? quantity;
  final String? purpose;
  final String? prescribedInstructions;
  final String? barcode;
  final String? appearance;
  final bool isActive;

  String get title => '$name $strength';
  String get subtitle => [quantity, prescribedInstructions].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  Map<String, dynamic> toJson() => {
        'id': id,
        'senior_id': seniorId,
        'name': name,
        'strength': strength,
        'dosage_form': dosageForm,
        'quantity': quantity,
        'purpose': purpose,
        'prescribed_instructions': prescribedInstructions,
        'barcode': barcode,
        'appearance': appearance,
        'is_active': isActive,
      };
}

class Schedule {
  Schedule({
    required this.id,
    required this.medicationId,
    required this.seniorId,
    required this.times,
    required this.weekdays,
    required this.startDate,
    this.endDate,
    required this.timezone,
    this.requireVerification = false,
    this.reminderMessage,
  });

  factory Schedule.fromJson(Map<String, dynamic> j) => Schedule(
        id: j['id'],
        medicationId: j['medication_id'],
        seniorId: j['senior_id'],
        times: List<String>.from(j['times']),
        weekdays: List<int>.from(j['weekdays']),
        startDate: DateTime.parse(j['start_date']),
        endDate: j['end_date'] == null ? null : DateTime.parse(j['end_date']),
        timezone: j['timezone'],
        requireVerification: j['require_verification'] ?? false,
        reminderMessage: j['reminder_message'],
      );

  final String id;
  final String medicationId;
  final String seniorId;
  final List<String> times; // "HH:MM" wall-clock in [timezone]
  final List<int> weekdays; // 0 = Mon .. 6 = Sun
  final DateTime startDate;
  final DateTime? endDate;
  final String timezone;
  final bool requireVerification;
  final String? reminderMessage;

  Map<String, dynamic> toJson() => {
        'id': id,
        'medication_id': medicationId,
        'senior_id': seniorId,
        'times': times,
        'weekdays': weekdays,
        'start_date': _d(startDate),
        'end_date': endDate == null ? null : _d(endDate!),
        'timezone': timezone,
        'require_verification': requireVerification,
        'reminder_message': reminderMessage,
      };

  static String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class Senior {
  Senior({required this.id, required this.fullName, required this.language, required this.timezone, this.birthYear, this.hasLogin = false, this.phone});
  factory Senior.fromJson(Map<String, dynamic> j) => Senior(
        id: j['id'],
        fullName: j['full_name'],
        language: j['language'] ?? 'en',
        timezone: j['timezone'] ?? 'UTC',
        birthYear: j['birth_year'],
        hasLogin: j['has_login'] ?? false,
        phone: j['phone'],
      );
  final String? phone;
  final String id;
  final String fullName;
  final String language;
  final String timezone;
  final int? birthYear;
  final bool hasLogin;
}
