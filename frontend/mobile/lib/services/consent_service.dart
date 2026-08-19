import 'package:flutter/foundation.dart';
import '../models/result.dart';
import 'auth_service.dart';
import 'typed_api_client.dart';

/// สถานะความยินยอม PDPA ของผู้ใช้ — มาจาก GET /api/consents/status
@immutable
class ConsentStatus {
  final bool consented;
  final String currentVersion;
  final String? consentedVersion;

  const ConsentStatus({
    required this.consented,
    required this.currentVersion,
    this.consentedVersion,
  });

  factory ConsentStatus.fromJson(Map<String, dynamic> json) => ConsentStatus(
    consented: json['consented'] == true,
    currentVersion: json['current_version']?.toString() ?? '',
    consentedVersion: json['consented_version']?.toString(),
  );
}

/// สัญญาของ service เช็ค/ให้ความยินยอม PDPA — คุย /api/consents* จริง
abstract class ConsentService {
  Future<Result<ConsentStatus>> fetchStatus();
  Future<Result<void>> giveConsent(String policyVersion);
}

class HttpConsentService implements ConsentService {
  final TypedApiClient _client;
  const HttpConsentService(this._client);

  @override
  Future<Result<ConsentStatus>> fetchStatus() => _client.getJson<ConsentStatus>(
    '/api/consents/status',
    decode: (json) => ConsentStatus.fromJson(json as Map<String, dynamic>),
  );

  @override
  Future<Result<void>> giveConsent(String policyVersion) => _client.postJson<void>(
    '/api/consents',
    body: {'consent_type': 'health_data_pdpa', 'policy_version': policyVersion},
    decode: (_) {},
  );
}

ConsentService createConsentService() {
  final client = TypedApiClient(tokenProvider: () => AuthService().token);
  return HttpConsentService(client);
}
