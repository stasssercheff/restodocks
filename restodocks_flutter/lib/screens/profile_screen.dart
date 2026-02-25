import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../services/profile_service.dart';
import '../models/models.dart';

/// Экран профиля пользователя
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  double? _earnedSalary;
  double? _currentMonthSalary;
  bool _loadingSalary = true;

  @override
  void initState() {
    super.initState();
    _loadSalaryData();
  }

  Future<void> _loadSalaryData() async {
    final account = context.read<AccountManagerSupabase>();
    final employee = account.currentEmployee;
    final establishment = account.establishment;

    if (employee == null || establishment == null) {
      setState(() => _loadingSalary = false);
      return;
    }

    // Рассчитываем зарплату только если у сотрудника есть должность (не владелец без роли)
    if (employee.hasRole('owner') && employee.roles.length <= 1) {
      setState(() => _loadingSalary = false);
      return;
    }

    try {
      final earned = await ProfileService.calculateEarnedSalary(employee, establishment.id);
      final currentMonth = await ProfileService.calculateCurrentMonthSalary(employee, establishment.id);

      if (mounted) {
        setState(() {
          _earnedSalary = earned;
          _currentMonthSalary = currentMonth;
          _loadingSalary = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingSalary = false);
      }
    }
  }

  void _showEditProfile(BuildContext context) {
    final account = context.read<AccountManagerSupabase>();
    final emp = account.currentEmployee;
    if (emp == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ProfileEditDialog(
        employee: emp,
        onSaved: (updated) async {
          await account.updateEmployee(updated);
          if (ctx.mounted) {
            Navigator.of(ctx).pop();
            setState(() {});
          }
        },
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountManager = context.watch<AccountManagerSupabase>();
    final currentEmployee = accountManager.currentEmployee;
    final establishment = accountManager.establishment;
    final localization = context.watch<LocalizationService>();

    if (currentEmployee == null || establishment == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isOwner = currentEmployee.hasRole('owner');
    final hasPosition = !currentEmployee.hasRole('owner') || currentEmployee.roles.length > 1;

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())
            : null,
        title: Text(localization.t('profile')),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _showEditProfile(context),
            tooltip: localization.t('edit_profile'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Компания
            _buildCompanySection(establishment, localization),

            if (isOwner) ...[
              const SizedBox(height: 24),
              _buildPinCodeSection(establishment, localization),
            ],

            const SizedBox(height: 24),

            // Основная информация профиля
            _buildProfileInfo(currentEmployee, establishment, localization, isOwner),

            const SizedBox(height: 24),

            // Личный график и ЗП (если есть должность)
            if (hasPosition) ...[
              _buildScheduleAndSalarySection(currentEmployee, establishment, localization),
              const SizedBox(height: 24),
            ],

            // Выход
            _buildLogoutSection(localization),
          ],
        ),
      ),
    );
  }

  void _copyPin(BuildContext context, String pinCode) {
    Clipboard.setData(ClipboardData(text: pinCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.read<LocalizationService>().t('pin_copied'))),
    );
  }

  Widget _buildPinCodeSection(Establishment establishment, LocalizationService localization) {
    final loc = localization;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.t('generated_pin'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              loc.t('pin_auto_hint'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      establishment.pinCode,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  onPressed: () => _copyPin(context, establishment.pinCode),
                  icon: const Icon(Icons.copy),
                  tooltip: loc.t('copy_pin'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanySection(Establishment establishment, LocalizationService localization) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localization.t('company'),
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              establishment.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileInfo(Employee employee, Establishment establishment, LocalizationService localization, bool isOwner) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Фото профиля
            Center(
              child: _buildAvatar(employee, 80),
            ),
            const SizedBox(height: 16),

            // Имя и фамилия
            Text(
              employee.fullName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),

            // Должность
            const SizedBox(height: 8),
            Text(
              employee.roleDisplayName,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),

            // Email
            const SizedBox(height: 8),
            Text(
              employee.email,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleAndSalarySection(Employee employee, Establishment establishment, LocalizationService localization) {
    final currencySymbol = employee.currencySymbol;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Личный график
        ListTile(
          leading: const Icon(Icons.calendar_month),
          title: const Text('Личный график'),
          subtitle: const Text('График непосредственно этого сотрудника'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/schedule'),
        ),

        // ЗП за отработанный период
        ListTile(
          leading: const Icon(Icons.payments),
          title: const Text('ЗП за отработанный период'),
          subtitle: _loadingSalary
              ? const Text('Загрузка...')
              : Text(_earnedSalary != null
                  ? ProfileService.formatSalary(_earnedSalary!, currencySymbol)
                  : 'Недоступно'),
        ),

        // ЗП за текущий календарный месяц
        ListTile(
          leading: const Icon(Icons.account_balance_wallet),
          title: const Text('ЗП за текущий календарный месяц'),
          subtitle: _loadingSalary
              ? const Text('Загрузка...')
              : Text(_currentMonthSalary != null
                  ? ProfileService.formatSalary(_currentMonthSalary!, currencySymbol)
                  : 'Недоступно'),
        ),
      ],
    );
  }

  Widget _buildLogoutSection(LocalizationService localization) {
    return ListTile(
      leading: const Icon(Icons.logout, color: Colors.red),
      title: const Text(
        'Выход',
        style: TextStyle(color: Colors.red),
      ),
      onTap: () => _logout(context),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final accountManager = context.read<AccountManagerSupabase>();
    await accountManager.logout();
    if (context.mounted) context.go('/login');
  }

  Widget _buildAvatar(Employee emp, double size) {
    if (emp.avatarUrl != null && emp.avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: emp.avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(color: Colors.grey[300], child: const Icon(Icons.person, size: 40)),
          errorWidget: (_, __, ___) => _avatarPlaceholder(size),
        ),
      );
    }
    return _avatarPlaceholder(size);
  }

  Widget _avatarPlaceholder(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.person, size: size * 0.5, color: Colors.grey),
    );
  }
}

/// Редактирование профиля: имя, фамилия, фото — виджет по центру экрана
class _ProfileEditDialog extends StatefulWidget {
  const _ProfileEditDialog({required this.employee, required this.onSaved, required this.onCancel});

  final Employee employee;
  final Future<void> Function(Employee) onSaved;
  final VoidCallback onCancel;

  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _surnameController;
  String? _avatarUrl;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final fn = widget.employee.fullName;
    final parts = fn.split(' ');
    _nameController = TextEditingController(text: parts.isNotEmpty ? parts.first : fn);
    _surnameController = TextEditingController(
      text: widget.employee.surname ?? (parts.length > 1 ? parts.sublist(1).join(' ') : ''),
    );
    _avatarUrl = widget.employee.avatarUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final loc = context.read<LocalizationService>();
    final isGallery = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.photo_library), title: Text(loc.t('photo_from_gallery')), onTap: () => Navigator.pop(ctx, true)),
            ListTile(leading: const Icon(Icons.camera_alt), title: Text(loc.t('photo_from_camera')), onTap: () => Navigator.pop(ctx, false)),
          ],
        ),
      ),
    );
    if (isGallery == null || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: isGallery ? ImageSource.gallery : ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;

      final bytes = await file.readAsBytes();
      final supabase = SupabaseService();
      const bucket = 'avatars';
      final fileName = '${widget.employee.id}.jpg';
      await supabase.client.storage.from(bucket).uploadBinary(fileName, bytes, fileOptions: FileOptions(upsert: true));
      final url = supabase.client.storage.from(bucket).getPublicUrl(fileName);
      if (mounted) setState(() => _avatarUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}');
    } catch (e) {
      if (mounted) {
        final errStr = e.toString();
        final isBucketNotFound = errStr.contains('Bucket not found') || errStr.contains('404');
        setState(() {
          _error = isBucketNotFound
              ? '${context.read<LocalizationService>().t('photo_upload_error')}: bucket "avatars" не найден. Создайте его в Supabase Dashboard: Storage → New bucket → имя "avatars" → Public bucket.'
              : '${context.read<LocalizationService>().t('photo_upload_error')}: $e';
          _isLoading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.read<LocalizationService>().t('name_required'));
      return;
    }
    final surname = _surnameController.text.trim();
    final fullName = surname.isEmpty ? name : '$name $surname';
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final updated = widget.employee.copyWith(
        fullName: fullName,
        surname: surname.isEmpty ? '' : surname,
        avatarUrl: _avatarUrl ?? widget.employee.avatarUrl,
      );
      await widget.onSaved(updated);
    } catch (e) {
      if (mounted) setState(() {
        _isLoading = false;
        final msg = e.toString().toLowerCase();
        _error = (msg.contains('payment') || msg.contains('column') || msg.contains('pgrst'))
            ? context.read<LocalizationService>().t('employee_save_error_schema')
            : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.read<LocalizationService>();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(loc.t('edit_profile'), style: theme.textTheme.titleLarge),
                    IconButton(icon: const Icon(Icons.close), onPressed: widget.onCancel),
                  ],
                ),
                const SizedBox(height: 24),
                Center(
                  child: GestureDetector(
                    onTap: _isLoading ? null : _pickPhoto,
                    child: Stack(
                      children: [
                        _avatarUrl != null
                            ? ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: _avatarUrl!,
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => _avatarPlaceholder(120),
                                  errorWidget: (_, __, ___) => _avatarPlaceholder(120),
                                ),
                              )
                            : _avatarPlaceholder(120),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: theme.colorScheme.primary,
                            child: Icon(Icons.camera_alt, color: theme.colorScheme.onPrimary, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(child: Text(loc.t('tap_to_change_photo'), style: theme.textTheme.bodySmall)),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: loc.t('name'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _surnameController,
                  decoration: InputDecoration(
                    labelText: loc.t('surname'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.badge),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: widget.onCancel, child: Text(loc.t('cancel') ?? 'Отмена'))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isLoading ? null : _save,
                        child: _isLoading ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)) : Text(loc.t('save')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatarPlaceholder(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Colors.grey[300], shape: BoxShape.circle),
      child: Icon(Icons.person, size: size * 0.5, color: Colors.grey[600]),
    );
  }
}
