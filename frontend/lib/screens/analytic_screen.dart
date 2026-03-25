// ignore_for_file: control_flow_in_finally

import 'dart:math';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models.dart';

class AiAnalyticsScreen extends StatefulWidget {
  const AiAnalyticsScreen({
    super.key,
    required this.apiClient,
    required this.subscriptions,
  });

  final ApiClient apiClient;
  final List<Subscription> subscriptions;

  @override
  State<AiAnalyticsScreen> createState() => _AiAnalyticsScreenState();
}

class _AiAnalyticsScreenState extends State<AiAnalyticsScreen> {
  AiInsights? _insights;
  ChartData? _chartData;
  bool _loading = false;
  bool _chartLoading = false;
  String? _error;
  String? _chartError;
  String? _lastSignature;

  @override
  void initState() {
    super.initState();
    _lastSignature = _buildSignature(widget.subscriptions);
    _refreshAnalytics();
  }

  @override
  void didUpdateWidget(covariant AiAnalyticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _buildSignature(widget.subscriptions);
    if (_lastSignature != signature) {
      _lastSignature = signature;
      _refreshAnalytics();
    }
  }

  Future<void> _refreshAnalytics() async {
    await Future.wait([
      _fetchInsights(),
      _fetchChartData(),
    ]);
  }

  Future<void> _fetchInsights() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final insights = await widget.apiClient.getAiInsights();
      if (!mounted) return;
      setState(() {
        _insights = insights;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _fetchChartData() async {
    setState(() {
      _chartLoading = true;
      _chartError = null;
    });
    try {
      final data = await widget.apiClient.getChartData();
      if (!mounted) return;
      setState(() {
        _chartData = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chartError = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _chartLoading = false;
      });
    }
  }

  String _buildSignature(List<Subscription> subscriptions) {
    final tokens = subscriptions
        .map((s) => [
              s.id ?? '',
              s.name,
              s.price.toStringAsFixed(2),
              s.billingPeriod,
              s.interval,
              s.nextBillingDate.toIso8601String(),
              s.category,
            ].join('|'))
        .toList()
      ..sort();
    return tokens.join('||');
  }

  @override
  Widget build(BuildContext context) {
    final fallbackToLocal =
        _chartData != null &&
        _chartData!.monthly.isEmpty &&
        _chartData!.quarterly.isEmpty &&
        _chartData!.byCategory.isEmpty &&
        widget.subscriptions.isNotEmpty;
    final chartData = fallbackToLocal ? null : _chartData;
    final categoryStats = chartData != null
        ? chartData.byCategory
            .map((e) => LabelSpend(label: e.category, monthlyCost: e.amount / 12))
            .toList()
        : _buildCategoryStats(widget.subscriptions);
    final monthlyStats = chartData != null
        ? chartData.monthly
            .map((e) => LabelSpend(label: e.period, monthlyCost: e.amount))
            .toList()
        : _buildServiceStats(widget.subscriptions);
    final quarterlyStats = chartData != null
        ? chartData.quarterly
            .map((e) => LabelSpend(label: e.period, monthlyCost: e.amount))
            .toList()
        : _buildPeriodStats(widget.subscriptions);
    final totalMonthly = chartData != null
        ? chartData.forecast12Months / 12
        : categoryStats.fold<double>(0, (sum, e) => sum + e.monthlyCost);
    final topCategory = chartData != null
        ? (chartData.byCategory.isNotEmpty ? chartData.byCategory.first.category : '—')
        : (categoryStats.isNotEmpty ? categoryStats.first.label : '—');
    return RefreshIndicator(
      onRefresh: _refreshAnalytics,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'AI-анализ подписок',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _SummaryCard(
            totalMonthly: totalMonthly,
            subscriptionsCount: widget.subscriptions.length,
            topCategory: topCategory,
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Расходы по категориям (в месяц)',
            data: categoryStats,
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Прогноз по месяцам (12 мес)',
            data: monthlyStats,
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Прогноз по кварталам',
            data: quarterlyStats,
          ),
          const SizedBox(height: 12),
          _AiInsightsCard(
            insights: _insights,
            loading: _loading,
            error: _error,
          ),
          if (_chartError != null) ...[
            const SizedBox(height: 8),
            Text(
              'Статистика получена локально: $_chartError',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_chartLoading && _chartData == null) ...[
            const SizedBox(height: 6),
            Text(
              'Обновляем статистику...',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  List<LabelSpend> _buildCategoryStats(List<Subscription> subscriptions) {
    final totals = <String, double>{};
    for (final sub in subscriptions) {
      final monthly = _monthlyCost(sub);
      totals[sub.category] = (totals[sub.category] ?? 0) + monthly;
    }
    final stats = totals.entries.map((e) => LabelSpend(label: e.key, monthlyCost: e.value)).toList();
    stats.sort((a, b) => b.monthlyCost.compareTo(a.monthlyCost));
    return stats;
  }

  List<LabelSpend> _buildServiceStats(List<Subscription> subscriptions) {
    final totals = <String, double>{};
    for (final sub in subscriptions) {
      final monthly = _monthlyCost(sub);
      totals[sub.name] = (totals[sub.name] ?? 0) + monthly;
    }
    final stats = totals.entries.map((e) => LabelSpend(label: e.key, monthlyCost: e.value)).toList();
    stats.sort((a, b) => b.monthlyCost.compareTo(a.monthlyCost));
    return _collapseTop(stats, limit: 8);
  }

  List<LabelSpend> _buildPeriodStats(List<Subscription> subscriptions) {
    final totals = <String, double>{};
    for (final sub in subscriptions) {
      final monthly = _monthlyCost(sub);
      final label = _periodLabel(sub.billingPeriod);
      totals[label] = (totals[label] ?? 0) + monthly;
    }
    final stats = totals.entries.map((e) => LabelSpend(label: e.key, monthlyCost: e.value)).toList();
    stats.sort((a, b) => b.monthlyCost.compareTo(a.monthlyCost));
    return stats;
  }

  double _monthlyCost(Subscription sub) {
    final interval = max(1, sub.interval);
    switch (sub.billingPeriod) {
      case 'month':
        return sub.price / interval;
      case 'year':
        return sub.price / (12 * interval);
      case 'week':
        return sub.price * (4.33 / interval);
      default:
        return sub.price;
    }
  }

  String _periodLabel(String value) {
    switch (value) {
      case 'month':
        return 'Ежемесячно';
      case 'year':
        return 'Ежегодно';
      case 'week':
        return 'Еженедельно';
      default:
        return value;
    }
  }

  List<LabelSpend> _collapseTop(List<LabelSpend> items, {int limit = 8}) {
    if (items.length <= limit) return items;
    final top = items.take(limit).toList();
    final otherSum = items.skip(limit).fold<double>(0, (sum, e) => sum + e.monthlyCost);
    top.add(LabelSpend(label: 'Другое', monthlyCost: otherSum));
    return top;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalMonthly,
    required this.subscriptionsCount,
    required this.topCategory,
  });

  final double totalMonthly;
  final int subscriptionsCount;
  final String topCategory;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Сводка', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _SummaryRow(label: 'Подписок', value: subscriptionsCount.toString()),
            _SummaryRow(label: 'Сумма в месяц', value: _formatPrice(totalMonthly)),
            _SummaryRow(label: 'Топ категория', value: topCategory),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.data});

  final String title;
  final List<LabelSpend> data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (data.isEmpty)
              Text(
                'Нет данных для построения графика.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              CategoryBarChart(data: data),
          ],
        ),
      ),
    );
  }
}

class CategoryBarChart extends StatelessWidget {
  const CategoryBarChart({super.key, required this.data});

  final List<LabelSpend> data;

  @override
  Widget build(BuildContext context) {
    final maxValue = data.map((e) => e.monthlyCost).reduce(max);
    final barColor = Theme.of(context).colorScheme.primary;
    const barWidth = 44.0;
    const labelWidth = 72.0;
    return SizedBox(
      height: 200,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: data.map((item) {
              final heightFactor = maxValue == 0 ? 0.0 : item.monthlyCost / maxValue;
              return _BarColumn(
                label: item.label,
                value: item.monthlyCost,
                heightFactor: heightFactor,
                color: barColor,
                barWidth: barWidth,
                labelWidth: labelWidth,
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _BarColumn extends StatelessWidget {
  const _BarColumn({
    required this.label,
    required this.value,
    required this.heightFactor,
    required this.color,
    required this.barWidth,
    required this.labelWidth,
  });

  final String label;
  final double value;
  final double heightFactor;
  final Color color;
  final double barWidth;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(_formatPrice(value), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            width: barWidth,
            height: 20 + 92 * heightFactor,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: labelWidth,
            height: 18,
            child: Tooltip(
              message: label,
              waitDuration: const Duration(milliseconds: 400),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiInsightsCard extends StatelessWidget {
  const _AiInsightsCard({
    required this.insights,
    required this.loading,
    required this.error,
  });

  final AiInsights? insights;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Рекомендации ИИ', style: Theme.of(context).textTheme.titleMedium),
                if (loading)
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (error != null)
              Text(
                'Не удалось получить анализ: $error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (insights == null)
              Text(
                'Данных пока нет. Потяните вниз, чтобы обновить.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else ...[
              _ScoreRow(score: insights!.rationalityScore),
              if (insights!.shortCommentRu.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(insights!.shortCommentRu, style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: 12),
              _ChipSection(title: 'Рекомендуем отменить', items: insights!.recommendCancel),
              const SizedBox(height: 8),
              _ChipSection(title: 'Рекомендуем оставить', items: insights!.recommendKeep),
              const SizedBox(height: 8),
              _ChipSection(title: 'Альтернативы', items: insights!.alternatives),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    final normalized = score <= 1 ? score * 100 : score;
    final clamped = normalized.clamp(0, 100).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Рациональность подписок: ${clamped.toStringAsFixed(0)}%', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LinearProgressIndicator(
            value: clamped / 100,
            minHeight: 10,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _ChipSection extends StatelessWidget {
  const _ChipSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 6),
        if (items.isEmpty)
          Text('Нет данных', style: Theme.of(context).textTheme.bodySmall)
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: items
                .map((item) => Chip(
                      label: Text(item),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList(),
          ),
      ],
    );
  }
}

String _formatPrice(double value) {
  return '${value.toStringAsFixed(0)} ₽/мес';
}
