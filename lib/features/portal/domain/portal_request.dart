class PortalRequest {
  const PortalRequest({
    required this.id,
    required this.gymId,
    this.planId,
    this.planName,
    this.planPrice,
    this.planCurrency,
    required this.firstName,
    required this.lastName,
    required this.phone,
    this.email,
    this.kind = 'new_membership',
    this.status = 'pending',
    this.memberId,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String gymId;
  final String? planId;
  final String? planName;
  final double? planPrice;
  final String? planCurrency;
  final String firstName;
  final String lastName;
  final String phone;
  final String? email;
  final String kind;
  final String status;
  final String? memberId;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get fullName => '$firstName $lastName'.trim();

  factory PortalRequest.fromJson(Map<String, dynamic> json) {
    final plans = json['plans'] as Map<String, dynamic>?;
    return PortalRequest(
      id: json['id'] as String,
      gymId: json['gym_id'] as String,
      planId: json['plan_id'] as String?,
      planName: plans?['name'] as String?,
      planPrice: (plans?['price'] as num?)?.toDouble(),
      planCurrency: plans?['currency'] as String?,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String?,
      kind: json['kind'] as String? ?? 'new_membership',
      status: json['status'] as String? ?? 'pending',
      memberId: json['member_id'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}
