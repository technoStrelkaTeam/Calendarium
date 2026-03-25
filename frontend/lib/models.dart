import 'dart:convert';

class UserProfile {
  final int id;
  final String name;
  final String? username;
  final String email;

  UserProfile({
    required this.id,
    required this.name,
    required this.username,
    required this.email,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as int,
      name: json['name'] as String,
      username: json['username'] as String?,
      email: json['email'] as String,
    );
  }
}

class AuthResult {
  final String token;
  final UserProfile user;

  AuthResult({required this.token, required this.user});
}

class Subscription {
  final int? id;
  final String name;
  final double price;
  final String billingPeriod;
  final int interval;
  final DateTime nextBillingDate;
  final String category;

  Subscription({
    this.id,
    required this.name,
    required this.price,
    required this.billingPeriod,
    required this.interval,
    required this.nextBillingDate,
    required this.category,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    final rawPeriod = (json['type_interval'] ?? json['billing_period']) as String;
    final normalizedPeriod = _normalizeBillingPeriod(rawPeriod);
    return Subscription(
      id: json['id'] as int?,
      name: json['name'] as String,
      price: ((json['cost'] ?? json['price']) as num).toDouble(),
      billingPeriod: normalizedPeriod,
      interval: (json['interval'] ?? 1) as int,
      nextBillingDate: DateTime.parse(
        (json['next_pay'] ?? json['next_billing_date']) as String,
      ),
      category: json['category'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'cost': price,
      'type_interval': billingPeriod,
      'interval': interval,
      'next_pay': nextBillingDate.toIso8601String(),
      'category': category,
    };
  }

  static String _normalizeBillingPeriod(String value) {
    switch (value) {
      case 'monthly':
        return 'month';
      case 'yearly':
        return 'year';
      case 'weekly':
        return 'week';
      default:
        return value;
    }
  }
}

class SubscriptionDraft {
  final String name;
  final double price;
  final String billingPeriod;
  final int interval;
  final DateTime nextBillingDate;
  final String category;

  SubscriptionDraft({
    required this.name,
    required this.price,
    required this.billingPeriod,
    required this.interval,
    required this.nextBillingDate,
    required this.category,
  });
}

class AiInsights {
  final double rationalityScore;
  final List<String> recommendCancel;
  final List<String> recommendKeep;
  final List<String> alternatives;
  final String shortCommentRu;

  AiInsights({
    required this.rationalityScore,
    required this.recommendCancel,
    required this.recommendKeep,
    required this.alternatives,
    required this.shortCommentRu,
  });

  factory AiInsights.fromJson(Map<String, dynamic> json) {
    return AiInsights(
      rationalityScore: _asDouble(json['rationality_score']) ?? 0,
      recommendCancel: _stringList(json['recommend_cancel']),
      recommendKeep: _stringList(json['recommend_keep']),
      alternatives: _stringList(json['alternatives'], preferAlternative: true),
      shortCommentRu: (json['short_comment_ru'] ?? '').toString(),
    );
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static List<String> _stringList(dynamic value, {bool preferAlternative = false}) {
    final seen = <String>{};
    if (value is List) {
      return value
          .map((e) => _stringFromValue(e, preferAlternative: preferAlternative))
          .where((e) => e.trim().isNotEmpty)
          .where((e) => _isAlternativeValid(e, preferAlternative: preferAlternative))
          .where((e) => seen.add(_normalizeKey(e)))
          .toList();
    }
    if (value is Map) {
      final parsed = _stringFromValue(value, preferAlternative: preferAlternative);
      if (parsed.trim().isEmpty) return <String>[];
      if (!_isAlternativeValid(parsed, preferAlternative: preferAlternative)) return <String>[];
      if (!seen.add(_normalizeKey(parsed))) return <String>[];
      return [parsed];
    }
    if (value is String && value.trim().isNotEmpty) {
      final trimmed = value.trim();
      if (!_isAlternativeValid(trimmed, preferAlternative: preferAlternative)) return <String>[];
      if (!seen.add(_normalizeKey(trimmed))) return <String>[];
      return [trimmed];
    }
    return <String>[];
  }

  static String _stringFromValue(dynamic value, {bool preferAlternative = false}) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Map) {
      final alternative =
          value['alternative'] ?? value['alt'] ?? value['replacement'] ?? value['recommendation'];
      final service = value['service'] ?? value['name'] ?? value['title'] ?? value['label'];
      if (preferAlternative && alternative != null && service != null) {
        return '${service.toString()} → ${alternative.toString()}';
      }
      if (preferAlternative && alternative != null) {
        return alternative.toString();
      }
      final name = service ?? alternative;
      if (name != null) {
        return name.toString();
      }
      return jsonEncode(value);
    }
    return value.toString();
  }

  static bool _isAlternativeValid(String value, {required bool preferAlternative}) {
    if (!preferAlternative) return true;
    final parts = value.split('→').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.length < 2) return true;
    final left = _normalizeKey(parts.first);
    final right = _normalizeKey(parts.last);
    return left != right;
  }

  static String _normalizeKey(String value) {
    return value
        .toLowerCase()
        .replaceAll('→', '')
        .replaceAll(RegExp(r'[^a-z0-9а-яё]+', caseSensitive: false), '')
        .trim();
  }
}

class LabelSpend {
  LabelSpend({required this.label, required this.monthlyCost});
  final String label;
  final double monthlyCost;
}

class PeriodAmount {
  PeriodAmount({required this.period, required this.amount});
  final String period;
  final double amount;

  factory PeriodAmount.fromJson(Map<String, dynamic> json) {
    return PeriodAmount(
      period: json['period']?.toString() ?? '',
      amount: _toDouble(json['amount']),
    );
  }
}

class CategoryAmount {
  CategoryAmount({required this.category, required this.amount, required this.percent});
  final String category;
  final double amount;
  final double percent;

  factory CategoryAmount.fromJson(Map<String, dynamic> json) {
    return CategoryAmount(
      category: json['category']?.toString() ?? '',
      amount: _toDouble(json['amount']),
      percent: _toDouble(json['percent']),
    );
  }
}

class ChartData {
  ChartData({
    required this.monthly,
    required this.quarterly,
    required this.byCategory,
    required this.forecast12Months,
  });

  final List<PeriodAmount> monthly;
  final List<PeriodAmount> quarterly;
  final List<CategoryAmount> byCategory;
  final double forecast12Months;

  factory ChartData.fromJson(Map<String, dynamic> json) {
    final monthly = _periodList(json['monthly']);
    final quarterly = _periodList(json['quarterly']);
    final byCategory = _categoryList(json['by_category'] ?? json['byCategory']);
    final forecast12Months =
        _asDouble(json['forecast_12_months'] ?? json['forecast12Months']) ?? 0;
    return ChartData(
      monthly: monthly,
      quarterly: quarterly,
      byCategory: byCategory,
      forecast12Months: forecast12Months,
    );
  }

  static List<PeriodAmount> _periodList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map<String, dynamic>>()
          .map((e) => PeriodAmount.fromJson(e))
          .toList();
    }
    return <PeriodAmount>[];
  }

  static List<CategoryAmount> _categoryList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map<String, dynamic>>()
          .map((e) => CategoryAmount.fromJson(e))
          .toList();
    }
    return <CategoryAmount>[];
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
