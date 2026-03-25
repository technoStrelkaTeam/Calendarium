// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../api/api_client.dart';
import '../models.dart';
import '../services/notification_service.dart';
import 'analytic_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.apiClient,
    required this.user,
    required this.onLogout,
    required this.onUserUpdate,
  });

  final ApiClient apiClient;
  final UserProfile user;
  final VoidCallback onLogout;
  final ValueChanged<UserProfile> onUserUpdate;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  bool _loading = false;
  String? _error;
  String? _importError;
  final List<Subscription> _subscriptions = [];
  final _imapLoginController = TextEditingController();
  final _imapPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _imapLoginController.text = widget.user.email;
    _loadSubscriptionsFromLocal();
    _syncSubscriptionsFromServer();
  }

  @override
  void dispose() {
    _imapLoginController.dispose();
    _imapPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadSubscriptionsFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final subscriptionsJson = prefs.getStringList('subscriptions') ?? [];
    setState(() {
      _subscriptions.clear();
      _subscriptions.addAll(
        subscriptionsJson.map((json) => Subscription.fromJson(jsonDecode(json))),
      );
    });
    final updated = await _normalizeOverdueSubscriptions();
    if (!updated) {
      await _scheduleNotifications();
    }
  }

  Future<void> _saveSubscriptionsToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final subscriptionsJson = _subscriptions.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList('subscriptions', subscriptionsJson);
  }

  Future<bool> _normalizeOverdueSubscriptions({bool syncToServer = false}) async {
    if (_subscriptions.isEmpty) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var changed = false;
    final updatedSubscriptions = <Subscription>[];
    final toSync = <Subscription>[];

    for (final subscription in _subscriptions) {
      final adjustedDate = _rollForwardDate(
        subscription.nextBillingDate,
        subscription.billingPeriod,
        subscription.interval,
        today,
      );
      if (_isSameDay(adjustedDate, subscription.nextBillingDate)) {
        updatedSubscriptions.add(subscription);
      } else {
        final updated = Subscription(
          id: subscription.id,
          name: subscription.name,
          price: subscription.price,
          billingPeriod: subscription.billingPeriod,
          interval: subscription.interval,
          nextBillingDate: adjustedDate,
          category: subscription.category,
        );
        updatedSubscriptions.add(updated);
        if (syncToServer && updated.id != null) {
          toSync.add(updated);
        }
        changed = true;
      }
    }

    if (!changed) return false;

    if (mounted) {
      setState(() {
        _subscriptions
          ..clear()
          ..addAll(updatedSubscriptions);
      });
    } else {
      _subscriptions
        ..clear()
        ..addAll(updatedSubscriptions);
    }

    await _saveSubscriptionsToLocal();
    await _scheduleNotifications();

    if (syncToServer && toSync.isNotEmpty) {
      for (final subscription in toSync) {
        await widget.apiClient.updateSubscription(
          subscription.id!,
          SubscriptionDraft(
            name: subscription.name,
            price: subscription.price,
            billingPeriod: subscription.billingPeriod,
            interval: subscription.interval,
            nextBillingDate: subscription.nextBillingDate,
            category: subscription.category,
          ),
        );
      }
    }

    return true;
  }

  DateTime _rollForwardDate(
    DateTime date,
    String billingPeriod,
    int interval,
    DateTime today,
  ) {
    final step = interval < 1 ? 1 : interval;
    var current = DateTime(date.year, date.month, date.day);
    while (current.isBefore(today)) {
      current = _advanceDate(current, billingPeriod, step);
    }
    return current;
  }

  DateTime _advanceDate(DateTime date, String billingPeriod, int interval) {
    switch (billingPeriod) {
      case 'year':
        return _addMonths(date, 12 * interval);
      case 'month':
        return _addMonths(date, interval);
      case 'week':
        return date.add(Duration(days: 7 * interval));
      default:
        return date.add(Duration(days: 30 * interval));
    }
  }

  DateTime _addMonths(DateTime date, int monthsToAdd) {
    final monthIndex = date.month - 1 + monthsToAdd;
    final year = date.year + (monthIndex ~/ 12);
    final month = (monthIndex % 12) + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(year, month, day);
  }

  Future<void> _syncSubscriptionsFromServer() async {
    try {
      final serverSubscriptions = await widget.apiClient.getSubscriptions();
      setState(() {
        _subscriptions.clear();
        _subscriptions.addAll(serverSubscriptions);
      });
      final updated = await _normalizeOverdueSubscriptions(syncToServer: true);
      if (!updated) {
        await _saveSubscriptionsToLocal();
        await _scheduleNotifications();
      }
    } catch (e) {
      // If server fails, keep local data
    }
  }

  Future<void> _syncSubscriptionToServer(Subscription subscription) async {
    try {
      if (subscription.id == null) {
        final created = await widget.apiClient.createSubscription(SubscriptionDraft(
          name: subscription.name,
          price: subscription.price,
          billingPeriod: subscription.billingPeriod,
          interval: subscription.interval,
          nextBillingDate: subscription.nextBillingDate,
          category: subscription.category,
        ));
        final merged = _mergeCreatedSubscription(
          local: subscription,
          created: created,
        );
        setState(() {
          final index = _subscriptions.indexWhere((s) => s == subscription);
          if (index != -1) {
            _subscriptions[index] = merged;
          }
        });
        await _saveSubscriptionsToLocal();
      } else {
        await widget.apiClient.updateSubscription(subscription.id!, SubscriptionDraft(
          name: subscription.name,
          price: subscription.price,
          billingPeriod: subscription.billingPeriod,
          interval: subscription.interval,
          nextBillingDate: subscription.nextBillingDate,
          category: subscription.category,
        ));
      }
    } catch (e) {
      // Handle error
    }
  }

  Subscription _mergeCreatedSubscription({
    required Subscription local,
    required Subscription created,
  }) {
    final sameDay = _isSameDay(local.nextBillingDate, created.nextBillingDate);
    return Subscription(
      id: created.id,
      name: created.name,
      price: created.price,
      billingPeriod: created.billingPeriod,
      interval: created.interval,
      nextBillingDate: sameDay ? created.nextBillingDate : local.nextBillingDate,
      category: created.category,
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _editSubscription(Subscription subscription) async {
    final result = await showDialog<SubscriptionDraft>(
      context: context,
      builder: (context) => EditSubscriptionDialog(subscription: subscription),
    );
    if (result != null) {
      setState(() {
        _loading = true;
      });
      var updatedSuccessfully = false;
      var loadingCleared = false;
      try {
        final index = _subscriptions.indexOf(subscription);
        if (index != -1) {
          final updated = Subscription(
            id: subscription.id,
            name: result.name,
            price: result.price,
            billingPeriod: result.billingPeriod,
            interval: result.interval,
            nextBillingDate: result.nextBillingDate,
            category: result.category,
          );
          _subscriptions[index] = updated;
          await _saveSubscriptionsToLocal();
          updatedSuccessfully = true;
          if (mounted) {
            setState(() {
              _loading = false;
            });
            loadingCleared = true;
          }
          Future<void>(() async {
            await _syncSubscriptionToServer(updated);
          }).catchError((_) {});
          Future<void>(() async {
            await _scheduleNotifications();
          }).catchError((_) {});
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось обновить подписку')),
          );
        }
      } finally {
        if (mounted && !loadingCleared) {
          setState(() {
            _loading = false;
          });
        }
      }
      if (updatedSuccessfully && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Подписка обновлена')),
        );
      }
    }
  }

  

  void _removeSubscription(Subscription subscription) async {
    setState(() {
      _subscriptions.remove(subscription);
    });
    await _saveSubscriptionsToLocal();
    if (subscription.id != null) {
      try {
        await widget.apiClient.deleteSubscription(subscription.id!);
        await _scheduleNotifications();
      } catch (e) {
        // Re-add if server fails
        setState(() {
          _subscriptions.add(subscription);
        });
        await _saveSubscriptionsToLocal();
        await _scheduleNotifications();
      }
    }
  }

  Future<void> _loadSubscriptions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
    });
  }

  Future<void> _addSubscription(SubscriptionDraft draft) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) {
      return;
    }
    final subscription = Subscription(
      name: draft.name,
      price: draft.price,
      billingPeriod: draft.billingPeriod,
      interval: draft.interval,
      nextBillingDate: draft.nextBillingDate,
      category: draft.category,
    );
    setState(() {
      _subscriptions.add(subscription);
      _loading = false;
    });
    await _saveSubscriptionsToLocal();
    await _syncSubscriptionToServer(subscription);
    await _scheduleNotifications();
  }

  Future<void> _importFromEmail() async {
    setState(() {
      _loading = true;
      _importError = null;
    });

    final imapLogin = _imapLoginController.text.trim();
    final imapPassword = _imapPasswordController.text;
    final parsed = <Subscription>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (imapLogin.isNotEmpty && imapPassword.isNotEmpty) {
      try {
        final response = await widget.apiClient.importFromImap(imapLogin, imapPassword);

        for (final entry in response.entries) {
          final name = entry.key;
          final item = entry.value;
          if (item is Map<String, dynamic>) {
            final cost = item['cost'];
            final price = cost != null ? double.tryParse(cost.toString()) ?? 0.0 : 0.0;
            final nextDate = today;
            if (price > 0) {
              final draft = SubscriptionDraft(
                name: name,
                price: price,
                billingPeriod: 'month',
                interval: 1,
                nextBillingDate: nextDate,
                category: 'Imported',
              );
              parsed.add(Subscription(
                name: draft.name,
                price: draft.price,
                billingPeriod: draft.billingPeriod,
                interval: draft.interval,
                nextBillingDate: draft.nextBillingDate,
                category: draft.category,
              ));
            }
          }
        }
      } catch (e) {
        _importError = e.toString();
      }
    } else {
      _importError = 'Введите логин и пароль IMAP для импорта.';
    }

    if (!mounted) {
      return;
    }

    setState(() {
      if (parsed.isEmpty) {
        _importError ??= 'Не удалось извлечь подписки из письма.';
      } else {
        _subscriptions.addAll(parsed);
        _importError = null;
      }
      _loading = false;
    });

    if (parsed.isNotEmpty) {
      await _saveSubscriptionsToLocal();
      for (final subscription in parsed) {
        await _syncSubscriptionToServer(subscription);
      }
      await _scheduleNotifications();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Импорт завершен: добавлено ${parsed.length} подписок')),
      );
    }
  }

  Future<void> _scheduleNotifications() async {
    await NotificationService.instance.scheduleForSubscriptions(_subscriptions);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pages = [
      ProfileView(apiClient: widget.apiClient, user: widget.user, onLogout: widget.onLogout, onUserUpdate: widget.onUserUpdate),
      SubscriptionList(
        subscriptions: _subscriptions,
        loading: _loading,
        error: _error,
        onRefresh: _loadSubscriptions,
        onRemove: _removeSubscription,
        onEdit: _editSubscription,
      ),
      AiAnalyticsScreen(
        apiClient: widget.apiClient,
        subscriptions: _subscriptions,
      ),
      AddSubscriptionForm(
        onSave: _addSubscription,
        loading: _loading,
      ),
      ImportSubscriptions(
        onImport: _importFromEmail,
        loading: _loading,
        error: _importError,
        imapLoginController: _imapLoginController,
        imapPasswordController: _imapPasswordController,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Центр подписок'),
        actions: [
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: pages,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        selectedItemColor: scheme.primary,
        unselectedItemColor: isDark ? scheme.onSurface.withOpacity(0.7) : scheme.onSurfaceVariant,
        backgroundColor: isDark ? scheme.surfaceVariant : scheme.surface,
        elevation: isDark ? 8 : 0,
        onTap: (value) {
          setState(() {
            _index = value;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Профиль',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Обзор',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome_outlined),
            label: 'AI-анализ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Добавить',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.email_outlined),
            label: 'Импорт',
          ),
        ],
      ),
    );
  }
}

class ProfileView extends StatefulWidget {
  const ProfileView({super.key, required this.apiClient, required this.user, required this.onLogout, required this.onUserUpdate});

  final ApiClient apiClient;
  final UserProfile user;
  final VoidCallback onLogout;
  final ValueChanged<UserProfile> onUserUpdate;

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  String? _findByEmailResult;
  bool _loading = false;
  late UserProfile _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
  }

  Future<void> _findByEmail() async {
    setState(() {
      _loading = true;
      _findByEmailResult = null;
    });
    try {
      final found = await widget.apiClient.getUserByEmail(widget.user.email);
      setState(() {
        _findByEmailResult = 'Найден пользователь: ${found.name} (${found.email})';
      });
    } catch (e) {
      setState(() {
        _findByEmailResult = 'Ошибка: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _testNotification() async {
    setState(() {
      _loading = true;
      _findByEmailResult = null;
    });
    try {
      final enabled = await NotificationService.instance.areNotificationsEnabled();
      if (!enabled) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Уведомления отключены в настройках устройства')),
        );
        return;
      }
      final exactAllowed = await NotificationService.instance.canScheduleExactAlarms();
      if (!exactAllowed) {
        final opened = await NotificationService.instance.requestExactAlarmPermission();
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось открыть настройки точных будильников')),
          );
        }
      }
      await NotificationService.instance.showTestNotification();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Тест отправлен: должно появиться сразу и через 10с')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка теста уведомлений: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _editProfile() async {
    final result = await showDialog<EditProfileResult>(
      context: context,
      builder: (context) => EditProfileDialog(user: _currentUser),
    );
    if (result != null) {
      setState(() {
        _loading = true;
      });
      try {
        final updated = await widget.apiClient.updateProfile(result.name, result.email);
        setState(() {
          _currentUser = updated;
        });
        widget.onUserUpdate(updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Профиль обновлен')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления: $e')),
        );
      } finally {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Данные пользователя',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _editProfile,
            icon: const Icon(Icons.edit),
            label: const Text('Редактировать'),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'ID', value: _currentUser.id.toString()),
                const SizedBox(height: 8),
                _InfoRow(label: 'Имя', value: _currentUser.name),
                const SizedBox(height: 8),
                _InfoRow(label: 'Username', value: _currentUser.username ?? '—'),
                const SizedBox(height: 8),
                _InfoRow(label: 'Email', value: _currentUser.email),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _loading ? null : _findByEmail,
          child: _loading
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Проверить по email'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _loading ? null : _testNotification,
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('Тест уведомления'),
        ),
        if (_findByEmailResult != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_findByEmailResult!),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class SubscriptionList extends StatelessWidget {
  const SubscriptionList({
    super.key,
    required this.subscriptions,
    required this.loading,
    required this.error,
    required this.onRefresh,
    this.onRemove,
    this.onEdit,
  });

  final List<Subscription> subscriptions;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final ValueChanged<Subscription>? onRemove;
  final ValueChanged<Subscription>? onEdit;

  @override
  Widget build(BuildContext context) {
    if (loading && subscriptions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Активные подписки',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          if (subscriptions.isEmpty && error == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Нет подписок. Добавьте первую подписку на вкладке "Добавить".',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ...subscriptions.map((subscription) => SubscriptionCard(
                subscription,
                onRemove: onRemove,
                onEdit: onEdit,
              )),
        ],
      ),
    );
  }
}

class SubscriptionCard extends StatelessWidget {
  const SubscriptionCard(
    this.subscription, {
    super.key,
    this.onRemove,
    this.onEdit,
  });

  final Subscription subscription;
  final ValueChanged<Subscription>? onRemove;
  final ValueChanged<Subscription>? onEdit;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat.yMMMd();
    return Card(
      child: ListTile(
        title: Text(subscription.name),
        subtitle: Text(
          '${subscription.category} • ${subscription.billingPeriod}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${subscription.price.toStringAsFixed(2)} RUB'),
                Text(
                  formatter.format(subscription.nextBillingDate),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (onEdit != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Редактировать',
                onPressed: () => onEdit!(subscription),
              ),
            ],
            if (onRemove != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Удалить',
                onPressed: () => onRemove!(subscription),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AddSubscriptionForm extends StatefulWidget {
  const AddSubscriptionForm({super.key, required this.onSave, required this.loading});

  final Future<void> Function(SubscriptionDraft draft) onSave;
  final bool loading;

  @override
  State<AddSubscriptionForm> createState() => _AddSubscriptionFormState();
}

class _AddSubscriptionFormState extends State<AddSubscriptionForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _categoryController = TextEditingController();
  String _billingPeriod = 'month';
  DateTime _nextBillingDate = DateTime.now().add(const Duration(days: 30));

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    if (price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите действительную цену')),
      );
      return;
    }
    final draft = SubscriptionDraft(
      name: _nameController.text.trim(),
      price: price,
      billingPeriod: _billingPeriod,
      interval: 1,
      nextBillingDate: _nextBillingDate,
      category: _categoryController.text.trim().isEmpty
          ? 'Other'
          : _categoryController.text.trim(),
    );
    await widget.onSave(draft);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Подписка добавлена')),
    );
    _formKey.currentState!.reset();
    _nameController.clear();
    _priceController.clear();
    _categoryController.text = 'Streaming';
    setState(() {
      _billingPeriod = 'month';
      _nextBillingDate = DateTime.now().add(const Duration(days: 30));
    });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _nextBillingDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date != null) {
      setState(() {
        _nextBillingDate = date;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat.yMMMd();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Добавить подписку',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Название сервиса',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите название';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Цена (RUB)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите цену';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: 'Категория',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _billingPeriod,
                decoration: const InputDecoration(
                  labelText: 'Период выставления счета',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'month', child: Text('Ежемесячно')),
                  DropdownMenuItem(value: 'year', child: Text('Ежегодно')),
                  DropdownMenuItem(value: 'week', child: Text('Еженедельно')),
                ],
                onChanged: widget.loading
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _billingPeriod = value;
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text('Следующий платеж: ${formatter.format(_nextBillingDate)}'),
                  ),
                  TextButton(
                    onPressed: widget.loading ? null : _pickDate,
                    child: const Text('Выберете дату'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.loading ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(widget.loading ? 'Сохранение...' : 'Сохранить подписку'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class EditProfileResult {
  final String name;
  final String email;

  EditProfileResult({required this.name, required this.email});
}

class EditProfileDialog extends StatefulWidget {
  const EditProfileDialog({super.key, required this.user});

  final UserProfile user;

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _emailController = TextEditingController(text: widget.user.email);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Редактировать профиль'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Имя'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Введите имя';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Введите email';
                }
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                  return 'Введите корректный email';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(EditProfileResult(
                name: _nameController.text.trim(),
                email: _emailController.text.trim(),
              ));
            }
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class EditSubscriptionDialog extends StatefulWidget {
  const EditSubscriptionDialog({super.key, required this.subscription});

  final Subscription subscription;

  @override
  State<EditSubscriptionDialog> createState() => _EditSubscriptionDialogState();
}

class _EditSubscriptionDialogState extends State<EditSubscriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _categoryController;
  late String _billingPeriod;
  late DateTime _nextBillingDate;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.subscription.name);
    _priceController = TextEditingController(text: widget.subscription.price.toString());
    _categoryController = TextEditingController(text: widget.subscription.category);
    _billingPeriod = widget.subscription.billingPeriod;
    _nextBillingDate = widget.subscription.nextBillingDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Редактировать подписку'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Название'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите название';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(labelText: 'Цена'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите цену';
                  }
                  final price = double.tryParse(value.replaceAll(',', '.'));
                  if (price == null || price <= 0) {
                    return 'Введите действительную цену';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _billingPeriod,
                decoration: const InputDecoration(labelText: 'Период оплаты'),
                items: const [
                  DropdownMenuItem(value: 'month', child: Text('Ежемесячно')),
                  DropdownMenuItem(value: 'year', child: Text('Ежегодно')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _billingPeriod = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(labelText: 'Категория'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final price = double.parse(_priceController.text.replaceAll(',', '.'));
              Navigator.of(context).pop(SubscriptionDraft(
                name: _nameController.text.trim(),
                price: price,
                billingPeriod: _billingPeriod,
                interval: widget.subscription.interval,
                nextBillingDate: _nextBillingDate,
                category: _categoryController.text.trim().isEmpty
                    ? 'Other'
                    : _categoryController.text.trim(),
              ));
            }
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class ImportSubscriptions extends StatelessWidget {
  const ImportSubscriptions({
    super.key,
    required this.onImport,
    required this.loading,
    required this.error,
    required this.imapLoginController,
    required this.imapPasswordController,
  });

  final Future<void> Function() onImport;
  final bool loading;
  final String? error;
  final TextEditingController imapLoginController;
  final TextEditingController imapPasswordController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Импорт из электронной почты',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Text(
            'Импортировать подписки по IMAP (логин/пароль).',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: imapLoginController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'IMAP login (email)',
              helperText: 'Используется email из профиля по умолчанию',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: imapPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'IMAP password',
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: loading ? null : onImport,
            icon: const Icon(Icons.play_arrow),
            label: Text(loading ? 'Импорт...' : 'Запустить импорт'),
          ),
        ],
      ),
    );
  }
}
