import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mime/mime.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../updates/client_updates.dart';
import '../updates/update_widgets.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _name = TextEditingController();
  String _accountId = '', _busy = '';
  String? _error, _message;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _current(String id, int epoch) => mounted && ref.read(apiProvider).epoch == epoch && ref.read(sessionProvider).asData?.value?.id == id;

  Future<void> _saveProfile() async {
    if (_busy.isNotEmpty) return;
    final id = _accountId, name = _name.text.trim();
    final epoch = ref.read(apiProvider).epoch;
    if (name.isEmpty) { setState(() => _error = '昵称不能为空'); return; }
    setState(() { _busy = 'profile'; _error = null; _message = null; });
    try {
      await ref.read(sessionProvider.notifier).updateProfile(name);
      if (_current(id, epoch)) {
        setState(() {
          _name.text = ref.read(sessionProvider).asData!.value!.displayName;
          _message = '个人资料已保存';
        });
      }
    } catch (error) {
      if (_current(id, epoch)) setState(() => _error = errorMessage(error));
    } finally {
      if (_current(id, epoch)) setState(() => _busy = '');
    }
  }

  Future<void> _uploadAvatar() async {
    if (_busy.isNotEmpty) return;
    final id = _accountId;
    final epoch = ref.read(apiProvider).epoch;
    setState(() { _busy = 'avatar'; _error = null; _message = null; });
    try {
      final file = await openFile(acceptedTypeGroups: const [XTypeGroup(label: '头像图片', extensions: ['png', 'jpg', 'jpeg', 'webp'], uniformTypeIdentifiers: ['public.image'])]);
      if (file == null || !_current(id, epoch)) return;
      final bytes = await file.readAsBytes();
      if (!_current(id, epoch)) return;
      final mime = lookupMimeType(file.name, headerBytes: bytes);
      if (!['image/png', 'image/jpeg', 'image/webp'].contains(mime)) throw const ApiException('请选择 PNG、JPEG 或 WebP 图片');
      await ref.read(sessionProvider.notifier).updateAvatar(bytes, mime!);
      if (_current(id, epoch)) {
        ref.invalidate(imageProvider(ref.read(sessionProvider).asData!.value!.avatarUrl));
        setState(() => _message = '头像已更新');
      }
    } catch (error) {
      if (_current(id, epoch)) setState(() => _error = errorMessage(error));
    } finally {
      if (_current(id, epoch)) setState(() => _busy = '');
    }
  }

  Future<void> _setTheme(String? value) async {
    if (value == null || _busy.isNotEmpty) return;
    final id = _accountId;
    final epoch = ref.read(apiProvider).epoch;
    setState(() { _busy = 'theme'; _error = null; _message = null; });
    try {
      await ref.read(themeModeProvider.notifier).setMode(ThemeMode.values.byName(value));
      if (_current(id, epoch)) setState(() => _message = '主题偏好已保存');
    } catch (error) {
      if (_current(id, epoch)) setState(() => _error = errorMessage(error));
    } finally {
      if (_current(id, epoch)) setState(() => _busy = '');
    }
  }

  Future<void> _logout() async {
    if (_busy.isNotEmpty) return;
    final id = _accountId;
    final epoch = ref.read(apiProvider).epoch;
    setState(() { _busy = 'logout'; _error = null; _message = null; });
    try {
      final warning = await ref.read(sessionProvider.notifier).logout();
      if (mounted && ref.read(sessionProvider).asData?.value == null) context.go('/login', extra: warning);
    } catch (error) {
      if (_current(id, epoch)) setState(() => _error = errorMessage(error));
    } finally {
      if (_current(id, epoch)) setState(() => _busy = '');
    }
  }

  Future<void> _checkIn() async {
    if (_busy.isNotEmpty) return;
    final id = _accountId, epoch = ref.read(apiProvider).epoch;
    setState(() { _busy = 'checkin'; _error = null; _message = null; });
    try {
      final result = await ref.read(apiProvider).post('/check-in');
      if (result['checkedIn'] != true) throw const ApiException('服务器未确认签到，请重新读取额度后核对');
      if (_current(id, epoch)) {
        ref.invalidate(creditsProvider);
        setState(() => _message = jsonString(result['message']).isNotEmpty ? jsonString(result['message']) : '签到成功，获得 ${jsonInt(result['granted'])} 积分');
      }
    } catch (error) {
      if (_current(id, epoch)) setState(() => _error = errorMessage(error));
    } finally {
      if (_current(id, epoch)) setState(() => _busy = '');
    }
  }

  Future<void> _redeem() async {
    if (_busy.isNotEmpty) return;
    final id = _accountId, epoch = ref.read(apiProvider).epoch;
    final granted = await showFDialog<int>(context: context, barrierDismissible: false, builder: (context, style, animation) => _RedeemDialog(style: style, animation: animation));
    if (_current(id, epoch) && granted != null) {
      ref.invalidate(creditsProvider);
      setState(() { _error = null; _message = '兑换成功，获得 $granted 积分'; });
    }
  }

  Widget _accountCard(UserAccount user) {
    final theme = context.theme;
    return FCard(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 24, children: [
        Row(spacing: 10, children: [Icon(FLucideIcons.userRound, size: 19, color: theme.colors.primary), Text('个人资料', style: theme.typography.display.md.copyWith(fontWeight: FontWeight.w600))]),
        Row(spacing: 18, children: [
          ClipOval(child: SizedBox(width: 76, height: 76, child: user.avatarUrl.isEmpty
              ? ColoredBox(color: theme.colors.secondary, child: Icon(FLucideIcons.userRound, color: theme.colors.mutedForeground, size: 30))
              : ServerImage(user.avatarUrl))),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
            Text(user.displayName.isEmpty ? '创作者' : user.displayName, style: theme.typography.display.lg.copyWith(fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
            FButton(variant: FButtonVariant.outline, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: _busy == 'avatar' ? const FCircularProgress() : const Icon(FLucideIcons.imagePlus, size: 15), onPress: _busy.isEmpty ? _uploadAvatar : null, child: Text(_busy == 'avatar' ? '正在上传' : '更换头像')),
          ])),
        ]),
        const FDivider(),
        FTextField(control: FTextFieldControl.managed(controller: _name), label: const Text('昵称'), hint: '你希望被怎样称呼', enabled: _busy.isEmpty, textInputAction: TextInputAction.done, onSubmit: (_) => _saveProfile()),
        FTextField(control: FTextFieldControl.managed(initial: TextEditingValue(text: user.email)), label: const Text('登录邮箱'), readOnly: true, description: const Text('用于登录与接收账号通知')), 
        FButton(mainAxisSize: MainAxisSize.min, prefix: _busy == 'profile' ? const FCircularProgress() : const Icon(FLucideIcons.check, size: 16), onPress: _busy.isEmpty ? _saveProfile : null, child: Text(_busy == 'profile' ? '正在保存' : '保存资料')),
      ]),
    ));
  }

  Widget _preferences() {
    final theme = context.theme;
    final mode = ref.watch(themeModeProvider);
    final credits = ref.watch(creditsProvider);
    return Column(spacing: 20, children: [
      FCard(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 18, children: [
        Row(spacing: 10, children: [Icon(FLucideIcons.sparkles, size: 19, color: theme.colors.primary), Text('创作额度', style: theme.typography.display.md.copyWith(fontWeight: FontWeight.w600)), const Spacer(), FButton.icon(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, semanticsLabel: '刷新创作额度', onPress: credits.isLoading ? null : () => ref.invalidate(creditsProvider), child: const Icon(FLucideIcons.refreshCw, size: 15))]),
        credits.when(
          data: (balance) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [Text(balance.toStringAsFixed(balance == balance.roundToDouble() ? 0 : 2), style: theme.typography.display.xl.copyWith(fontSize: 38, fontWeight: FontWeight.w500, letterSpacing: -1.5)), Text('平台模型使用账号积分，个人渠道由接口提供方计费。', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground))]),
          loading: () => const SizedBox(height: 72, child: Center(child: FCircularProgress(semanticsLabel: '正在读取额度'))),
          error: (error, _) => FAlert(variant: FAlertVariant.destructive, title: const Text('额度读取失败'), subtitle: Text(errorMessage(error))),
        ),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FButton(variant: FButtonVariant.outline, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: _busy == 'checkin' ? const FCircularProgress() : const Icon(FLucideIcons.calendarCheck, size: 15), onPress: _busy.isEmpty ? _checkIn : null, child: const Text('每日签到')),
          FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.ticket, size: 15), onPress: _busy.isEmpty ? _redeem : null, child: const Text('兑换积分')),
          FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.gift, size: 15), onPress: () => context.go('/affiliate'), child: const Text('邀请好友赚积分')),
        ]),
      ]))),
      FCard(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
        Row(spacing: 10, children: [Icon(FLucideIcons.palette, size: 19, color: theme.colors.primary), Text('外观', style: theme.typography.display.md.copyWith(fontWeight: FontWeight.w600))]),
        FSelect(items: const {'跟随系统': 'system', '浅色 · 灵感白': 'light', '深色 · 静夜黑': 'dark'}, control: FSelectControl.lifted(value: mode.name, onChange: _setTheme), enabled: _busy.isEmpty, label: const Text('主题模式'), description: const Text('在这个设备上使用你喜欢的创作氛围。')),
        Row(children: [Expanded(child: Text('界面语言', style: theme.typography.body.sm)), Text('简体中文', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground))]),
      ]))),
      FCard(child: Padding(padding: const EdgeInsets.all(AppSpace.xl), child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 14, children: [
        Row(spacing: 10, children: [Icon(FLucideIcons.info, size: 19, color: theme.colors.primary), Text('关于 AI Studio', style: theme.typography.display.md.copyWith(fontWeight: FontWeight.w600))]),
        ref.watch(packageInfoProvider).when(data: (info) => Text('客户端 ${info.version}${info.buildNumber.isEmpty ? '' : ' · ${info.buildNumber}'}', style: theme.typography.body.sm), loading: () => const FCircularProgress(), error: (_, _) => FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(packageInfoProvider), child: const Text('重新读取版本'))),
        Text('图片、视频与对话，在一个空间里接续灵感。', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground)),
      ]))),
      const SoftwareUpdateCard(),
      FCard(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
        Row(spacing: 10, children: [Icon(FLucideIcons.server, size: 19, color: theme.colors.primary), Text('当前服务', style: theme.typography.display.md.copyWith(fontWeight: FontWeight.w600))]),
        SelectableText(apiOrigin, style: theme.typography.body.sm),
        Text('账号、作品与素材保存在项目服务器。', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground, height: 1.6)),
        const FDivider(),
        Row(spacing: 8, children: [Icon(FLucideIcons.shieldCheck, size: 15, color: theme.colors.mutedForeground), Expanded(child: Text('登录会话由系统安全存储保管', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)))]),
      ]))),
    ]);
  }

  Widget _content(UserAccount? user) {
    if (user == null) return Column(spacing: 20, children: [const FAlert(title: Text('登录后管理你的账号')), FButton(onPress: () => context.go('/login'), child: const Text('前往登录'))]);
    if (_accountId != user.id) {
      _accountId = user.id;
      _name.text = user.displayName;
      _busy = '';
      _error = null;
      _message = null;
    }
    final theme = context.theme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 28, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [Text('个人设置', style: theme.typography.display.xl2), Text('你的账号，你的创作空间。', style: theme.typography.body.md.copyWith(color: theme.colors.mutedForeground))]),
      if (_error != null) FAlert(variant: FAlertVariant.destructive, icon: const Icon(FLucideIcons.circleAlert), title: const Text('操作未完成'), subtitle: Text(_error!)),
      if (_message != null) FAlert(icon: const Icon(FLucideIcons.check), title: Text(_message!)),
      LayoutBuilder(builder: (context, constraints) => AppLayout.isDesktop && constraints.maxWidth >= 820
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 24, children: [Expanded(flex: 5, child: _accountCard(user)), Expanded(flex: 4, child: _preferences())])
          : Column(spacing: 20, children: [_accountCard(user), _preferences()])),
      FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, prefix: _busy == 'logout' ? const FCircularProgress() : const Icon(FLucideIcons.logOut, size: 17), onPress: _busy.isEmpty ? _logout : null, child: Text(_busy == 'logout' ? '正在退出' : '退出登录')),
    ]);
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.all(AppLayout.isDesktop ? AppSpace.xxl : AppSpace.lg),
    child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1040), child: ref.watch(sessionProvider).when(
      data: _content,
      loading: () => const Padding(padding: EdgeInsets.all(60), child: Center(child: FCircularProgress(semanticsLabel: '正在读取账号'))),
      error: (error, _) => Column(spacing: 20, children: [FAlert(variant: FAlertVariant.destructive, title: const Text('账号读取失败'), subtitle: Text(errorMessage(error))), FButton(variant: FButtonVariant.outline, onPress: () => ref.invalidate(sessionProvider), child: const Text('重新读取'))]),
    ))),
  );
}

class _RedeemDialog extends ConsumerStatefulWidget {
  const _RedeemDialog({required this.style, required this.animation});
  final FDialogStyle style;
  final Animation<double> animation;
  @override
  ConsumerState<_RedeemDialog> createState() => _RedeemDialogState();
}

class _RedeemDialogState extends ConsumerState<_RedeemDialog> {
  final _code = TextEditingController();
  late final int _epoch;
  bool _saving = false;
  String? _error;
  @override
  void initState() { super.initState(); _epoch = ref.read(apiProvider).epoch; }
  @override
  void dispose() { _code.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_saving) return;
    final code = _code.text.trim(), api = ref.read(apiProvider);
    if (api.epoch != _epoch) { Navigator.pop(context); return; }
    if (code.isEmpty) { setState(() => _error = '请输入兑换码'); return; }
    setState(() { _saving = true; _error = null; });
    try {
      final result = await api.post('/redeem', {'code': code});
      if (result['redeemed'] != true) throw const ApiException('服务器未确认兑换，请重新读取额度后核对');
      if (mounted && api.epoch == _epoch) Navigator.pop(context, jsonInt(result['granted']));
    } catch (error) {
      if (mounted && api.epoch == _epoch) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((session) => session.asData?.value?.id), (previous, next) { if (previous != next && mounted) Navigator.pop(context); });
    return PopScope(canPop: !_saving, child: FDialog(style: widget.style, animation: widget.animation, builder: (context, style) => Padding(padding: const EdgeInsets.all(AppSpace.xl), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
      Text('兑换创作积分', style: style.titleTextStyle),
      FTextField(control: FTextFieldControl.managed(controller: _code), label: const Text('兑换码'), hint: '输入你的积分兑换码', autofocus: true, enabled: !_saving, textInputAction: TextInputAction.done, onSubmit: (_) => _submit()),
      if (_error != null) FAlert(variant: FAlertVariant.destructive, title: const Text('兑换未完成'), subtitle: Text(_error!)),
      Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: [FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, onPress: _saving ? null : () => Navigator.pop(context), child: const Text('取消')), FButton(mainAxisSize: MainAxisSize.min, prefix: _saving ? const FCircularProgress() : null, onPress: _saving ? null : _submit, child: Text(_saving ? '正在兑换' : '确认兑换'))]),
    ]))));
  }
}
