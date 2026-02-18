// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'employee.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Employee _$EmployeeFromJson(Map<String, dynamic> json) => Employee(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      password: json['password_hash'] as String,
      department: json['department'] as String,
      section: json['section'] as String?,
      roles: (json['roles'] as List<dynamic>).map((e) => e as String).toList(),
      establishmentId: json['establishment_id'] as String,
      personalPin: json['personal_pin'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      subscriptionPlan: json['subscription_plan'] as String?,
      paymentType: json['payment_type'] as String?,
      ratePerShift: (json['rate_per_shift'] as num?)?.toDouble(),
      hourlyRate: (json['hourly_rate'] as num?)?.toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$EmployeeToJson(Employee instance) => <String, dynamic>{
      'id': instance.id,
      'full_name': instance.fullName,
      'email': instance.email,
      'password_hash': instance.password,
      'department': instance.department,
      'section': instance.section,
      'roles': instance.roles,
      'establishment_id': instance.establishmentId,
      'personal_pin': instance.personalPin,
      'avatar_url': instance.avatarUrl,
      'subscription_plan': instance.subscriptionPlan,
      'payment_type': instance.paymentType,
      'rate_per_shift': instance.ratePerShift,
      'hourly_rate': instance.hourlyRate,
      'is_active': instance.isActive,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };
