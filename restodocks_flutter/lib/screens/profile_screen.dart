import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';
import '../models/models.dart';

/// Экран профиля пользователя
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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

    if (currentEmployee == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: localization.t('home'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Информация о профиле
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Фото профиля
                    Center(
                      child: _buildAvatar(currentEmployee, 100),
                    ),
                    const SizedBox(height: 16),

                    // Имя
                    Text(
                      currentEmployee.fullName,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),

                    // Должность и отдел
                    Text(
                      '${localization.t('role')}: ${currentEmployee.rolesDisplayText}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      '${localization.t('department')}: ${currentEmployee.departmentDisplayName}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                      textAlign: TextAlign.center,
                    ),

                    // Email
                    Text(
                      currentEmployee.email,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Информация о компании
            if (establishment != null) ...[
              Text(
                localization.t('company_info'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        establishment.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('${context.read<LocalizationService>().t('pin_label')}: ${establishment.pinCode}'),
                      if (establishment.phone != null) ...[
                        const SizedBox(height: 4),
                        Text('${context.read<LocalizationService>().t('phone_label')}: ${establishment.phone}'),
                      ],
                      if (establishment.email != null) ...[
                        const SizedBox(height: 4),
                        Text('${context.read<LocalizationService>().t('email_label')}: ${establishment.email}'),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            if (!currentEmployee.hasRole('owner')) ...[
              Text(
                localization.t('schedule'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: Text(localization.t('schedule')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/schedule'),
              ),
              ListTile(
                leading: const Icon(Icons.numbers),
                title: Text(localization.t('shift_count')),
                subtitle: Text(context.read<LocalizationService>().t('zero')),
                trailing: const Icon(Icons.chevron_right),
              ),
              const SizedBox(height: 24),
            ],

            Text(
              localization.t('data'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                    ListTile(leading: const Icon(Icons.person), title: Text(localization.t('name')), subtitle: Text(currentEmployee.fullName), trailing: const Icon(Icons.chevron_right), onTap: () => _showEditProfile(context)),
                  ListTile(leading: const Icon(Icons.email), title: Text(localization.t('email')), subtitle: Text(currentEmployee.email)),
                  ListTile(leading: const Icon(Icons.photo_camera), title: Text(localization.t('photo')), subtitle: Text(currentEmployee.avatarUrl != null ? localization.t('photo_set') : localization.t('photo_not_set')), trailing: const Icon(Icons.chevron_right), onTap: () => _showEditProfile(context)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              localization.t('inbox'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.inbox),
              title: Text(localization.t('inbox')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/notifications'),
            ),
            const SizedBox(height: 20),
            const Divider(),

            // Выход
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(
                localization.t('logout'),
                style: const TextStyle(color: Colors.red),
              ),
              onTap: () => _logout(context),
            ),
          ],
        ),
      ),
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
        setState(() {
          _error = '${context.read<LocalizationService>().t('photo_upload_error')}: $e';
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
