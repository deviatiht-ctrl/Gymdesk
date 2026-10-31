import 'package:supabase_flutter/supabase_flutter.dart';

/// Gestion des accès espace membre côté personnel, via l'Edge Function
/// `manage_member_account` (rôle service côté serveur : le client ne peut pas
/// créer/modifier un utilisateur Auth directement).
///
/// Déployer avec : supabase functions deploy manage_member_account
/// Mêmes variables d'environnement que manage_staff (SUPABASE_URL,
/// SUPABASE_SERVICE_ROLE_KEY, GYMDESK_ALLOWED_ORIGINS).
class MemberAccountAdmin {
  const MemberAccountAdmin(this.client);

  final SupabaseClient client;

  /// Crée ou réinitialise le mot de passe d'accès d'un membre ; le serveur
  /// envoie automatiquement les identifiants par email au membre.
  /// Renvoie l'email du compte et si l'email est parti, sinon lève
  /// [MemberAccountException] avec un code stable ('shared_account',
  /// 'email_required', 'weak_password', 'function_missing', …).
  Future<({String email, bool emailSent})> setPassword({
    required String gymId,
    required String memberId,
    required String email,
    required String password,
  }) async {
    final data = await _invoke({
      'action': 'set_password',
      'gym_id': gymId,
      'member_id': memberId,
      'email': email.trim().toLowerCase(),
      'password': password,
    });
    return (
      email: data['email']?.toString() ?? email.trim().toLowerCase(),
      emailSent: data['email_sent'] == true,
    );
  }

  /// Retire l'accès espace membre (délie le compte ; supprime le compte Auth
  /// s'il n'est utilisé nulle part ailleurs). Repli sur la policy RLS si la
  /// fonction n'est pas encore déployée.
  Future<void> revoke({required String gymId, required String memberId}) async {
    try {
      await _invoke({'action': 'revoke', 'gym_id': gymId, 'member_id': memberId});
    } on MemberAccountException catch (e) {
      if (e.code != 'function_missing') rethrow;
      await client
          .from('member_accounts')
          .delete()
          .eq('gym_id', gymId)
          .eq('member_id', memberId);
    }
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    FunctionResponse res;
    try {
      res = await client.functions.invoke('manage_member_account', body: body);
    } on FunctionException catch (e) {
      // invoke lève pour toute réponse non-2xx : récupérer le vrai code
      // d'erreur du corps JSON plutôt que masquer en « network ».
      final details = e.details;
      if (e.status == 404) throw const MemberAccountException('function_missing');
      if (details is Map && details['error'] is String) {
        throw MemberAccountException(details['error'] as String);
      }
      throw MemberAccountException(switch (e.status) {
        401 || 403 => 'access_denied',
        _ => 'error_${e.status}',
      });
    } catch (_) {
      throw const MemberAccountException('network');
    }
    if (res.status == 404) throw const MemberAccountException('function_missing');
    final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    if (res.status >= 300 || data['error'] != null) {
      throw MemberAccountException(data['error']?.toString() ?? 'error_${res.status}');
    }
    return data;
  }
}

class MemberAccountException implements Exception {
  const MemberAccountException(this.code);
  final String code;
  @override
  String toString() => 'MemberAccountException($code)';
}

/// Libellé FR des codes d'erreur de l'accès membre côté personnel.
String memberAccountError(String code) => switch (code) {
      'function_missing' =>
        'Fonction serveur non déployée : exécutez « supabase functions deploy manage_member_account ».',
      'shared_account' =>
        'Cet email est déjà utilisé par un autre compte (personnel ou autre gym). Choisissez un autre email ou laissez le membre utiliser « Mot de passe oublié ».',
      'email_required' => 'Un email valide est requis pour créer l’accès.',
      'weak_password' => 'Mot de passe trop faible (8 caractères minimum).',
      'access_denied' => 'Action réservée au personnel de ce gym.',
      'origin_denied' =>
        'Domaine non autorisé par le serveur : ajoutez https://securgym.com à GYMDESK_ALLOWED_ORIGINS dans les secrets des Edge Functions.',
      'rate_limited' => 'Trop de demandes. Patientez quelques minutes.',
      'network' => 'Connexion Internet indisponible. Réessayez.',
      _ => 'Une erreur est survenue. Réessayez.',
    };
