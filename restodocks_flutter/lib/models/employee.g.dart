// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'employee.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Employee _$EmployeeFromJson(Map<String, dynamic> json) => Employee(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      surname: json['surname'] as String?,
      email: json['email'] as String,
      password: json['password_hash'] as String? ?? '',
      department: json['department'] as String,
      section: json['section'] as String?,
      roles: (json['roles'] as List<dynamic>).map((e) => e as String).toList(),
      establishmentId: json['establishment_id'] as String,
      personalPin: json['personal_pin'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      subscriptionPlan: json['subscription_plan'] as String?,
      preferredLanguage: json['preferred_language'] as String? ?? 'ru',
      preferredCurrency: json['preferred_currency'] as String?,
      gettingStartedShown: json['getting_started_shown'] as bool? ?? false,
      firstSessionAt: json['first_session_at'] == null
          ? null
          : DateTime.parse(json['first_session_at'] as String),
      paymentType: json['payment_type'] as String?,
      ratePerShift: (json['rate_per_shift'] as num?)?.toDouble(),
      hourlyRate: (json['hourly_rate'] as num?)?.toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      dataAccessEnabled: json['data_access_enabled'] as bool? ?? false,
      canEditOwnSchedule: json['can_edit_own_schedule'] as bool? ?? false,
      ownerAccessLevel: json['owner_access_level'] as String? ?? 'full',
      employmentStatus: json['employment_status'] as String? ?? 'permanent',
      employmentStartDate: json['employment_start_date'] == null
          ? null
          : DateTime.parse(json['employment_start_date'] as String),
      employmentEndDate: json['employment_end_date'] == null
          ? null
          : DateTime.parse(json['employment_end_date'] as String),
      birthday: json['birthday'] == null
          ? null
          : DateTime.parse(json['birthday'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$EmployeeToJson(Employee instance) => <String, dynamic>{
      'id': instance.id,
      'full_name': instance.fullName,
      'surname': instance.surname,
      'email': instance.email,
      'password_hash': instance.password,
      'department': instance.department,
      'section': instance.section,
      'roles': instance.roles,
      'establishment_id': instance.establishmentId,
      'personal_pin': instance.personalPin,
      'avatar_url': instance.avatarUrl,
      'subscription_plan': instance.subscriptionPlan,
      'preferred_language': instance.preferredLanguage,
      'preferred_currency': instance.preferredCurrency,
      'getting_started_shown': instance.gettingStartedShown,
      'first_session_at': instance.firstSessionAt?.toIso8601String(),
      'payment_type': instance.paymentType,
      'rate_per_shift': instance.ratePerShift,
      'hourly_rate': instance.hourlyRate,
      'is_active': instance.isActive,
      'data_access_enabled': instance.dataAccessEnabled,
      'can_edit_own_schedule': instance.canEditOwnSchedule,
      'owner_access_level': instance.ownerAccessLevel,
      'employment_status': instance.employmentStatus,
      'employment_start_date': instance.employmentStartDate?.toIso8601String(),
      'employment_end_date': instance.employmentEndDate?.toIso8601String(),
      'birthday': instance.birthday?.toIso8601String(),
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };
