import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

class ApiConfig {
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String defaultBaseUrl() {
    if (_envBaseUrl.isNotEmpty) {
      return _envBaseUrl;
    }
    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }
    return 'http://127.0.0.1:8000';
  }
}

class ApiClient {
  ApiClient({String? baseUrl}) : _baseUrl = baseUrl ?? ApiConfig.defaultBaseUrl();

  final String _baseUrl;
  String? _token;

  void updateToken(String? token) {
    _token = token;
  }

  Future<AuthResult> register(String name, String username, String email, String password) async {
    await _post(
      '/users/register',
      body: {
        'name': name,
        'username': username,
        'email': email,
        'password': password,
      },
    );
    final token = await _requestToken(username, password);
    final user = await _fetchMe(token: token);
    return AuthResult(token: token, user: user);
  }

  Future<AuthResult> login(String email, String password) async {
    final token = await _requestToken(email, password);
    final user = await _fetchMe(token: token);
    return AuthResult(token: token, user: user);
  }

  Future<String> _requestToken(String username, String password) async {
    final uri = Uri.parse('$_baseUrl/users/token');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': username, 'password': password},
    );
    final json = _decode(response);
    final token = json['access_token'];
    if (token == null) {
      throw ApiException('Token not returned by server');
    }
    return token as String;
  }

  Future<UserProfile> _fetchMe({required String token}) async {
    final uri = Uri.parse('$_baseUrl/users/me');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    final json = _decode(response);
    return UserProfile.fromJson(json);
  }

  Future<UserProfile> getUserByEmail(String email) async {
    final uri = Uri.parse('$_baseUrl/users/getByEmail/$email');
    final response = await http.get(
      uri,
      headers: _headers(),
    );
    final json = _decode(response);
    return UserProfile.fromJson(json);
  }

  Future<bool> isEmailTaken(String email) async {
    final uri = Uri.parse('$_baseUrl/users/getByEmail/$email');
    final response = await http.get(uri, headers: _headers());
    if (response.statusCode == 404) {
      return false;
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      return false;
    }
    if (response.statusCode >= 400) {
      _decode(response);
    }
    return true;
  }

  Future<Map<String, dynamic>> importFromImap(String login, String password) async {
    final uri = Uri.parse('$_baseUrl/users/import-from-imap');
    final response = await http.post(
      uri,
      headers: _headers(),
      body: jsonEncode({'login': login, 'password': password}),
    );
    final json = _decode(response);
    final data = json['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return <String, dynamic>{};
  }

  Future<UserProfile> updateProfile(String name, String email) async {
    final uri = Uri.parse('$_baseUrl/users/me');
    final response = await http.put(
      uri,
      headers: _headers(),
      body: jsonEncode({'name': name, 'email': email}),
    );
    final json = _decode(response);
    return UserProfile.fromJson(json);
  }


  Future<List<Subscription>> getSubscriptions() async {
    final uri = Uri.parse('$_baseUrl/subscribes/me');
    final response = await http.get(uri, headers: _headers());
    final decoded = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final json = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      final message =
          json['detail']?.toString() ??
          json['error']?.toString() ??
          'Request failed (HTTP ${response.statusCode})';
      throw ApiException(message);
    }
    if (decoded is List) {
      return decoded.map((e) => Subscription.fromJson(e as Map<String, dynamic>)).toList();
    }
    return <Subscription>[];
  }

  Future<Subscription> createSubscription(SubscriptionDraft draft) async {
    final uri = Uri.parse('$_baseUrl/subscribes/me');
    final body = {
      'name': draft.name,
      'cost': draft.price,
      'type_interval': draft.billingPeriod,
      'interval': draft.interval,
      'next_pay': draft.nextBillingDate.toIso8601String(),
      'category': draft.category,
    };
    final response = await http.post(
      uri,
      headers: _headers(),
      body: jsonEncode(body),
    );
    final json = _decode(response);
    return Subscription.fromJson(json);
  }

  Future<void> updateSubscription(int id, SubscriptionDraft draft) async {
    final uri = Uri.parse('$_baseUrl/subscribes/me/$id');
    final body = {
      'name': draft.name,
      'cost': draft.price,
      'type_interval': draft.billingPeriod,
      'interval': draft.interval,
      'next_pay': draft.nextBillingDate.toIso8601String(),
      'category': draft.category,
    };
    await http.put(
      uri,
      headers: _headers(),
      body: jsonEncode(body),
    );
  }

  Future<void> deleteSubscription(int id) async {
    final uri = Uri.parse('$_baseUrl/subscribes/me/$id');
    await http.delete(uri, headers: _headers());
  }

  Future<AiInsights> getAiInsights() async {
    final uri = Uri.parse('$_baseUrl/subscribes/me/ai-analysis');
    final response = await http.get(uri, headers: _headers());
    final json = _decode(response);
    return AiInsights.fromJson(json);
  }

  Future<ChartData> getChartData() async {
    final uri = Uri.parse('$_baseUrl/subscribes/me/chart-data');
    final response = await http.get(uri, headers: _headers());
    final json = _decode(response);
    return ChartData.fromJson(json);
  }

  Future<http.Response> _post(String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = _headers();
    return http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
  }

  Map<String, String> _headers() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      json = <String, dynamic>{};
    }
    if (response.statusCode >= 400) {
      final message =
          json['detail']?.toString() ??
          json['error']?.toString() ??
          'Request failed (HTTP ${response.statusCode})';
      throw ApiException(message);
    }
    return json;
  }

}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
