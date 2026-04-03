import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/account_manager_supabase.dart';
import '../services/email_service.dart';
import '../utils/dev_log.dart';
import '../utils/person_name_format.dart';

/// После signUp без сессии (Confirm email) создаём employee только после подтверждения почты.
/// Данные формы сохраняются здесь и применяются в [tryComplete] после входа.
class PendingCoOwnerRegistration {
  PendingCoOwnerRegistration._();

  static const _kKey = 'pending_co_owner_registration_v1';

  static Future<void> save({
    required String email,
    required String token,
    required String firstName,
    required String surname,
    DateTime? birthday,
    String? languageCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kKey,
      jsonEncode({
        'email': email.trim().toLowerCase(),
        'token': token,
        'firstName': formatPersonNameField(firstName),
        'surname': formatPersonNameField(surname),
        if (birthday != null)
          'birthday': '${birthday.year.toString().padLeft(4, '0')}-${birthday.month.toString().padLeft(2, '0')}-${birthday.day.toString().padLeft(2, '0')}',
        if (languageCode != null && languageCode.trim().isNotEmpty)
          'languageCode': languageCode.trim().toLowerCase(),
      }),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }

  static Future<({Employee employee, Establishment establishment})?> tryComplete(
    AccountManagerSupabase account,
  ) async {
    if (!account.supabase.isAuthenticated) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return null;

    Map<String, dynamic> map;
    try {
      map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }

    final email = (map['email'] as String?)?.trim().toLowerCase();
    final current = account.supabase.currentUser?.email?.trim().toLowerCase();
    if (email == null || email.isEmpty || current == null || email != current) {
      return null;
    }

    final token = map['token'] as String?;
    final firstName = map['firstName'] as String? ?? '';
    final surname = map['surname'] as String? ?? '';
    final languageCode = map['languageCode'] as String?;
    final birthdayStr = map['birthday'] as String?;

    if (token == null || token.trim().isEmpty || firstName.trim().isEmpty) {
      return null;
    }

    try {
      final params = <String, dynamic>{
        'p_invitation_token': token.trim(),
        'p_full_name': formatPersonNameField(firstName),
        'p_surname': surname.trim().isEmpty ? null : formatPersonNameField(surname),
      };
      if (birthdayStr != null && birthdayStr.trim().isNotEmpty) {
        params['p_birthday'] = birthdayStr.trim();
      }

      final empRaw = await account.supabase.client.rpc(
        'create_co_owner_from_invitation',
        params: params,
      );

      final empMap = Map<String, dynamic>.from(empRaw as Map)..['password'] = '';
      final employee = Employee.fromJson(empMap);

      final estData = await account.supabase.client
          .from('establishments')
          .select()
          .eq('id', employee.establishmentId)
          .limit(1)
          .single();

      final establishment = Establishment.fromJson(
        Map<String, dynamic>.from(estData as Map),
      );

      // После подтверждения почты и RPC — письмо с данными co-owner (ссылка уже использована ранее).
      try {
        final fullName = surname.trim().isEmpty
            ? firstName.trim()
            : '${firstName.trim()} ${surname.trim()}';
        await EmailService().sendRegistrationEmail(
          isOwner: false,
          isCoOwner: true,
          to: email,
          companyName: establishment.name,
          email: email,
          fullName: fullName.trim().isEmpty ? null : fullName,
          registeredAtLocal: DateTime.now().toLocal().toString(),
          pinCode: establishment.pinCode,
          languageCode: languageCode,
        );
      } catch (e) {
        devLog('PendingCoOwnerRegistration: sendRegistrationEmail failed: $e');
      }

      await clear();
      return (employee: employee, establishment: establishment);
    } catch (e, st) {
      devLog('PendingCoOwnerRegistration.tryComplete: $e\n$st');
      return null;
    }
  }
}
