import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../data/api_client.dart';
import '../ui/kit.dart';
import 'record_details_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.onChanged});
  final Future<void> Function()? onChanged;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _cancel = CancelToken();
  Map<String, dynamic>? _data;
  Uint8List? _avatar;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/auth/mobile/account',
        cancelToken: _cancel,
      );
      Uint8List? avatar;
      if (response.data?['has_avatar'] == true) {
        final image = await dio.get<List<int>>(
          '/auth/mobile/avatar',
          options: Options(responseType: ResponseType.bytes),
          cancelToken: _cancel,
        );
        avatar = Uint8List.fromList(image.data!);
      }
      if (mounted) {
        setState(() {
          _data = response.data;
          _avatar = avatar;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(
    String title,
    List<EditField> fields,
    String path, {
    Map<String, dynamic>? initial,
    String? notice,
    Map<String, dynamic> extra = const {},
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ApiEditScreen(
          title: title,
          fields: fields,
          initial: initial ?? const {},
          notice: notice,
          save: (values) async {
            await dio.put(
              path,
              data: {...values, ...extra},
              cancelToken: _cancel,
            );
          },
        ),
      ),
    );
    if (saved == true && mounted) {
      await widget.onChanged?.call();
      await _load();
    }
  }

  Future<void> _upload() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      const types = XTypeGroup(
        label: 'Profile image',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
        uniformTypeIdentifiers: [
          'public.jpeg',
          'public.png',
          'org.webmproject.webp',
        ],
        mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
      );
      final file = await openFile(acceptedTypeGroups: [types]);
      if (file == null) return;
      if (await file.length() > 2 * 1024 * 1024) {
        throw ArgumentError('Choose an image smaller than 2 MB.');
      }
      final bytes = await file.readAsBytes();
      await dio.post(
        '/auth/mobile/avatar',
        data: FormData.fromMap({
          'avatar': MultipartFile.fromBytes(bytes, filename: file.name),
        }),
        cancelToken: _cancel,
      );
      if (mounted) {
        setState(() => _avatar = bytes);
        snack(context, 'Avatar saved.');
      }
    } catch (error) {
      if (mounted) snack(context, apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final palette = MdrrmoColors.of(context);
    return AppScaffold(
      header: pushedHeader(context, 'Account'),
      childPad: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          ContentFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_error != null) ...[
                  AppBanner(
                    tone: AppBannerTone.danger,
                    icon: AppIcons.alert,
                    message: apiErrorMessage(_error!),
                    action: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _busy ? null : _load,
                        child: const Text('Retry'),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (data != null) ...[
                  Surface(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (_avatar != null)
                              ClipOval(
                                child: Image.memory(
                                  _avatar!,
                                  width: 68,
                                  height: 68,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Icon(
                                    AppIcons.user,
                                    size: 52,
                                    color: palette.textMuted,
                                  ),
                                ),
                              )
                            else
                              InitialsAvatar(
                                '${data['name'] ?? 'User'}',
                                size: 64,
                              ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${data['name']}',
                                    style: MdrrmoTypography.titleLg.copyWith(
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${data['email']}',
                                    style: MdrrmoTypography.bodySm.copyWith(
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${data['contact']}',
                                    style: MdrrmoTypography.tabular(
                                      MdrrmoTypography.bodySm.copyWith(
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _upload,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                              ),
                              icon: const Icon(AppIcons.camera, size: 16),
                              label: const Text('Choose profile image'),
                            ),
                            if (data['resident'] == true)
                              FilledButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _edit(
                                        'Edit profile',
                                        const [
                                          EditField(
                                            'name',
                                            'Full name',
                                            max: 120,
                                          ),
                                          EditField(
                                            'contact',
                                            'Contact number',
                                            max: 20,
                                          ),
                                          EditField(
                                            'house_no',
                                            'House number',
                                            max: 60,
                                            required: false,
                                          ),
                                          EditField(
                                            'street',
                                            'Street',
                                            max: 120,
                                          ),
                                          EditField(
                                            'barangay',
                                            'Barangay',
                                            max: 120,
                                          ),
                                          EditField('city', 'City', max: 120),
                                          EditField(
                                            'province',
                                            'Province',
                                            max: 120,
                                          ),
                                        ],
                                        '/auth/mobile/account',
                                        initial: data,
                                      ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                ),
                                icon: const Icon(AppIcons.edit, size: 16),
                                label: const Text('Edit profile'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppSectionGroup(
                    title: 'Security',
                    subtitle: 'Keep your account credentials updated.',
                    children: [
                      AppRowItem(
                        leading: Icon(
                          AppIcons.lock,
                          size: 18,
                          color: palette.brand,
                        ),
                        title: 'Change password',
                        subtitle: 'Update your sign-in password',
                        showChevron: true,
                        enabled: !_busy,
                        onTap: () => _edit('Change password', const [
                          EditField(
                            'current_password',
                            'Current password',
                            secret: true,
                            max: 128,
                          ),
                          EditField(
                            'password',
                            'New password (at least 8 characters)',
                            secret: true,
                            max: 128,
                          ),
                          EditField(
                            'password_confirmation',
                            'Confirm new password',
                            secret: true,
                            max: 128,
                          ),
                        ], '/auth/mobile/password'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppSectionGroup(
                    title: 'Data retention & account status',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          '${data['retention_notice']}',
                          style: MdrrmoTypography.bodySm.copyWith(
                            color: palette.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ),
                      AppRowItem(
                        leading: Icon(
                          AppIcons.shieldAlert,
                          size: 18,
                          color: palette.danger,
                        ),
                        title: 'Request account deletion',
                        subtitle:
                            'Status: ${(data['deletion_request'] as Map?)?['status'] ?? 'None'}',
                        destructive: true,
                        showChevron: true,
                        enabled: !_busy,
                        onTap: () => _edit(
                          'Request account deletion',
                          const [
                            EditField(
                              'current_password',
                              'Current password',
                              secret: true,
                              max: 128,
                            ),
                            EditField(
                              'reason',
                              'Reason (optional)',
                              required: false,
                              max: 1000,
                              lines: 4,
                            ),
                          ],
                          '/auth/mobile/deletion-request',
                          notice:
                              'MDRRMO must review this request. Your account and emergency records remain available while review is pending.',
                        ),
                      ),
                      if ((data['deletion_request'] as Map?)?['status'] ==
                          'pending')
                        AppRowItem(
                          leading: Icon(
                            AppIcons.close,
                            size: 18,
                            color: palette.brand,
                          ),
                          title: 'Cancel deletion request',
                          subtitle: 'Keep your active MDRRMO account',
                          showChevron: true,
                          enabled: !_busy,
                          onTap: () => _edit(
                            'Cancel deletion request',
                            const [
                              EditField(
                                'current_password',
                                'Current password',
                                secret: true,
                                max: 128,
                              ),
                            ],
                            '/auth/mobile/deletion-request',
                            extra: {'cancel': true},
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
