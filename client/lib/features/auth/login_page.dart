import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../affiliate/affiliate_providers.dart';
import 'auth_repository.dart';

export 'auth_repository.dart' show AuthMode, AuthNotice;

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.mode = AuthMode.login, this.initialEmail = '', this.inviteCode = ''});
  final AuthMode mode;
  final String initialEmail, inviteCode;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _code = TextEditingController();
  final _captcha = TextEditingController();
  final _inviteCode = TextEditingController();
  CancelToken _pageToken = CancelToken();
  late AuthMode _mode;
  bool _verifying = false, _acceptTerms = false, _passwordMode = false, _busy = false, _sending = false, _captchaLoading = false;
  String _captchaId = '';
  Uint8List? _captchaImage;
  String? _error, _message, _captchaError;
  int _captchaRequest = 0, _operation = 0;

  bool get _locked => _busy || _sending;
  bool _current(int operation, ApiClient api, int epoch) => mounted && operation == _operation && api.epoch == epoch && !_pageToken.isCancelled;
  bool _usePassword(SiteData site) => !_verifying && (_mode != AuthMode.login || !site.emailCodeLogin || _passwordMode);
  bool _needsCode(SiteData site) => _verifying || _mode == AuthMode.reset || (_mode == AuthMode.login && !_usePassword(site));
  bool _needsMail(SiteData site) => _mode != AuthMode.login || _verifying || !_usePassword(site);

  @override
  void initState() {
    super.initState();
    _mode = widget.mode;
    _email.text = widget.initialEmail;
    _inviteCode.text = widget.inviteCode;
    _prepare();
  }

  @override
  void didUpdateWidget(covariant LoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode || oldWidget.initialEmail != widget.initialEmail || oldWidget.inviteCode != widget.inviteCode) {
      _pageToken.cancel('账号页面已切换');
      _pageToken = CancelToken();
      _captchaRequest++;
      _operation++;
      _mode = widget.mode;
      _verifying = _acceptTerms = _passwordMode = _busy = _sending = false;
      _error = _message = null;
      _email.text = widget.initialEmail;
      _inviteCode.text = widget.inviteCode;
      _password.clear();
      _confirmPassword.clear();
      _code.clear();
      _prepare();
    }
  }

  Future<void> _prepare() async {
    try {
      final site = await ref.read(siteProvider.future);
      if (mounted && site.captchaEnabled) await _loadCaptcha();
    } catch (_) {
      // The site provider renders its own loading and error states.
    }
  }

  @override
  void dispose() {
    _pageToken.cancel('账号页面已关闭');
    _captchaRequest++;
    _operation++;
    for (final controller in [_email, _password, _confirmPassword, _code, _captcha, _inviteCode]) { controller.dispose(); }
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    final request = ++_captchaRequest;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    setState(() {
      _captchaLoading = true;
      _captchaId = '';
      _captchaImage = null;
      _captchaError = null;
      _captcha.clear();
    });
    try {
      final data = await AuthRepository(api).request('/auth/captcha', token: _pageToken);
      final id = jsonString(data['id']);
      final image = UriData.parse(jsonString(data['image'])).contentAsBytes();
      if (id.isEmpty || image.isEmpty) throw const ApiException('图形验证码读取失败');
      if (mounted && request == _captchaRequest && api.epoch == epoch) setState(() { _captchaId = id; _captchaImage = image; });
    } catch (error) {
      if (mounted && request == _captchaRequest && api.epoch == epoch && !(error is ApiException && error.canceled)) setState(() => _captchaError = errorMessage(error));
    } finally {
      if (mounted && request == _captchaRequest) setState(() => _captchaLoading = false);
    }
  }

  Map<String, dynamic>? _credentials(SiteData site, {bool sendCode = false}) {
    final usePassword = _usePassword(site), needsCode = _needsCode(site);
    final email = _email.text.trim();
    final password = _password.text, code = _code.text.trim();
    String? error;
    if (email.isEmpty) { error = '请输入邮箱或账号'; }
    else if (_needsMail(site) && !site.emailConfigured) { error = '邮件服务尚未配置，请联系站点管理员'; }
    else if (!sendCode && usePassword && password.isEmpty) { error = '请输入密码'; }
    else if (!sendCode && usePassword && _mode != AuthMode.login && password.length < 8) { error = '密码至少 8 位'; }
    else if (!sendCode && usePassword && _mode != AuthMode.login && password != _confirmPassword.text) { error = '两次输入的密码不一致'; }
    else if (!sendCode && needsCode && !RegExp(r'^\d{6}$').hasMatch(code)) { error = '请输入 6 位邮箱验证码'; }
    else if (!sendCode && _mode == AuthMode.register && !_verifying && !_acceptTerms) { error = '请阅读并勾选同意用户协议与隐私政策'; }
    else if (site.captchaEnabled && (_captchaId.isEmpty || _captcha.text.trim().isEmpty)) { error = '请先填写图形验证码'; }
    if (error != null) { setState(() => _error = error); return null; }
    return {
      'email': email,
      if (!sendCode && usePassword) 'password': password,
      if (!sendCode && needsCode) 'code': code,
      if (!sendCode && _mode == AuthMode.register && !_verifying) 'acceptTerms': _acceptTerms,
      if (!sendCode && _mode == AuthMode.register && !_verifying && _inviteCode.text.trim().isNotEmpty) 'inviteCode': _inviteCode.text.trim(),
      if (site.captchaEnabled) 'captchaId': _captchaId,
      if (site.captchaEnabled) 'captchaCode': _captcha.text.trim(),
    };
  }

  Future<void> _sendCode(SiteData site) async {
    if (_locked) return;
    final body = _credentials(site, sendCode: true);
    if (body == null) return;
    final operation = ++_operation;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    setState(() { _sending = true; _error = _message = null; });
    try {
      final purpose = _verifying ? 'register' : _mode == AuthMode.reset ? 'reset' : 'login';
      final message = await AuthRepository(api).sendCode(body, purpose, _pageToken);
      if (_current(operation, api, epoch)) setState(() => _message = message);
    } catch (error) {
      if (_current(operation, api, epoch) && !(error is ApiException && error.canceled)) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted && operation == _operation) {
        setState(() => _sending = false);
        if (site.captchaEnabled && api.epoch == epoch) await _loadCaptcha();
      }
    }
  }

  Future<void> _submit(SiteData site) async {
    if (_locked || _captchaLoading) return;
    final body = _credentials(site);
    if (body == null) return;
    final operation = ++_operation;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    var refreshEpoch = epoch;
    setState(() { _busy = true; _error = _message = null; });
    try {
      if (_verifying || _mode == AuthMode.login) {
        final session = ref.read(sessionProvider.notifier);
        if (_verifying) { await session.verifyEmail(body, cancelToken: _pageToken); }
        else { await session.login(body, cancelToken: _pageToken); }
        if (mounted && operation == _operation && ref.read(sessionProvider).asData?.value != null) context.go('/explore');
      } else if (_mode == AuthMode.register) {
        final result = await AuthRepository(api).register(body, _pageToken);
        if (!_current(operation, api, epoch)) return;
        setState(() {
          _verifying = true;
          _email.text = result.email;
          _password.clear();
          _confirmPassword.clear();
          _code.clear();
          _message = result.emailSent ? result.message : '账号已创建，邮件发送未完成。请点击重发验证码；${result.message}';
        });
      } else {
        final message = await AuthRepository(api).resetPassword(body, _pageToken);
        if (!_current(operation, api, epoch)) return;
        String? cleanupWarning;
        try { await ref.read(sessionProvider.notifier).expire(); }
        catch (error) {
          if (error is ApiException && error.canceled) return;
          cleanupWarning = '密码已更新，但系统安全存储清理失败，请在登录前重试退出并核对账号会话。';
        }
        if (!mounted || operation != _operation || api.accountId.isNotEmpty) return;
        refreshEpoch = api.epoch;
        context.go(Uri(path: '/login', queryParameters: {'email': _email.text.trim()}).toString(), extra: AuthNotice(title: '密码已更新', message: message, warning: cleanupWarning));
      }
    } catch (error) {
      if (mounted && operation == _operation && !(error is ApiException && error.canceled)) {
        if (api.epoch == epoch && error is ApiException && error.verificationRequired) {
          setState(() { _verifying = true; _password.clear(); _confirmPassword.clear(); _code.clear(); _message = '请完成邮箱验证后继续，可重新发送注册验证码。'; _error = null; });
        } else if (api.epoch == epoch || ((_verifying || _mode == AuthMode.login) && api.accountId.isEmpty)) {
          refreshEpoch = api.epoch;
          setState(() => _error = errorMessage(error));
        }
      }
    } finally {
      if (mounted && operation == _operation) {
        setState(() => _busy = false);
        if (site.captchaEnabled && ref.read(sessionProvider).asData?.value == null && api.epoch == refreshEpoch) await _loadCaptcha();
      }
    }
  }

  void _changeMode(AuthMode mode, SiteData site, {bool verify = false}) {
    if (_locked) return;
    _operation++;
    setState(() {
      _mode = mode;
      _verifying = verify;
      _acceptTerms = _passwordMode = false;
      _error = _message = null;
      _password.clear();
      _confirmPassword.clear();
      _code.clear();
    });
    if (site.captchaEnabled) _loadCaptcha();
  }

  void _showAgreement(String title, String content) {
    showFDialog<void>(
      context: context,
      builder: (context, style, animation) => FDialog(
        style: style,
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
            Text(title, style: style.titleTextStyle),
            ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .55), child: SingleChildScrollView(child: SelectableText(content.isEmpty ? '站点尚未提供协议内容，请联系管理员' : content, style: style.bodyTextStyle))),
            FButton(onPress: () => Navigator.of(context).pop(), child: const Text('我知道了')),
          ]),
        ),
      ),
    );
  }

  Future<void> _setTheme(ThemeMode mode) async {
    try { await ref.read(themeModeProvider.notifier).setMode(mode); }
    catch (error) { if (mounted) setState(() => _error = errorMessage(error)); }
  }

  Widget _form(SiteData site) {
    final theme = context.theme;
    final usePassword = _usePassword(site), needsCode = _needsCode(site), mailUnavailable = _needsMail(site) && !site.emailConfigured;
    final title = _verifying ? '验证你的邮箱' : switch (_mode) { AuthMode.login => '欢迎回来', AuthMode.register => '创建你的账号', AuthMode.reset => '找回密码' };
    final description = _verifying ? '完成邮箱验证后，即可开始创作。' : switch (_mode) { AuthMode.login => '登录后，让想象成为你的下一件作品。', AuthMode.register => '使用邮箱注册，开启你的创作空间。', AuthMode.reset => '通过邮箱验证码设置新的账号密码。' };
    final program = _mode == AuthMode.register && !_verifying ? ref.watch(affiliateProgramProvider) : null;
    final submitLabel = _verifying ? '验证邮箱并登录' : switch (_mode) { AuthMode.login => '开始创作', AuthMode.register => '创建账号', AuthMode.reset => '重置密码' };
    return AutofillGroup(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
        Text(title, style: theme.typography.display.xl.copyWith(fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -1)),
        Text(description, style: theme.typography.body.md.copyWith(color: theme.colors.mutedForeground)),
        if (_mode == AuthMode.login && !_verifying && site.emailCodeLogin)
          Row(spacing: 8, children: [
            Expanded(child: FButton(variant: !usePassword ? FButtonVariant.secondary : FButtonVariant.ghost, onPress: _locked ? null : () => setState(() { _passwordMode = false; _error = _message = null; }), child: const Text('邮箱验证码'))),
            Expanded(child: FButton(variant: usePassword ? FButtonVariant.secondary : FButtonVariant.ghost, onPress: _locked ? null : () => setState(() { _passwordMode = true; _error = _message = null; }), child: const Text('管理员密码'))),
          ]),
        FTextField.email(control: FTextFieldControl.managed(controller: _email), label: Text(_mode == AuthMode.login && !_verifying && usePassword ? '邮箱或管理员账号' : '邮箱地址'), hint: 'name@example.com', enabled: !_locked && !_verifying, prefixBuilder: (_, _, _) => const Padding(padding: EdgeInsets.only(left: 14, right: 8), child: Icon(FLucideIcons.mail, size: 17))),
        if (needsCode)
          Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 10, children: [
            Expanded(child: FTextField(control: FTextFieldControl.managed(controller: _code), label: const Text('邮箱验证码'), hint: '输入 6 位邮件验证码', keyboardType: TextInputType.number, autofillHints: const [AutofillHints.oneTimeCode], enabled: !_locked, textInputAction: TextInputAction.done, onSubmit: (_) => _submit(site))),
            FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, prefix: _sending ? const FCircularProgress() : null, onPress: _locked || !site.emailConfigured || _captchaLoading ? null : () => _sendCode(site), child: Text(_sending ? '发送中' : _verifying ? '重发验证码' : '获取验证码')),
          ]),
        if (usePassword) ...[
          FTextField.password(control: FTextFieldControl.managed(controller: _password), label: Text(_mode == AuthMode.reset ? '新密码' : '密码'), hint: _mode == AuthMode.login ? '输入账号密码' : '设置至少 8 位密码', autofillHints: [_mode == AuthMode.login ? AutofillHints.password : AutofillHints.newPassword], enabled: !_locked, textInputAction: _mode == AuthMode.login ? TextInputAction.done : TextInputAction.next, onSubmit: _mode == AuthMode.login ? (_) => _submit(site) : null),
          if (_mode != AuthMode.login) FTextField.password(control: FTextFieldControl.managed(controller: _confirmPassword), label: const Text('确认密码'), hint: '再次输入密码', autofillHints: const [AutofillHints.newPassword], enabled: !_locked, textInputAction: TextInputAction.done, onSubmit: (_) => _submit(site)),
        ],
        if (_mode == AuthMode.register && !_verifying) ...[
          FTextField(control: FTextFieldControl.managed(controller: _inviteCode), label: const Text('邀请码（选填）'), hint: '输入邀请人的邀请码', enabled: !_locked, description: const Text('邀请关系由服务器核验，请核对邀请码。')),
          if (program?.asData?.value.enabled == true) Text('通过有效邀请注册并完成邮箱验证，新用户赠送 ${program!.asData!.value.inviteeGrant} 积分，邀请人赠送 ${program.asData!.value.inviterGrant} 积分。奖励以服务器实际到账为准。', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground))
          else if (program?.hasError == true) Row(children: [Expanded(child: Text('邀请规则暂时无法读取，可继续注册。', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground))), FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(affiliateProgramProvider), child: const Text('重新读取'))])
          else if (program?.isLoading == true) Text('正在读取邀请活动规则…', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
          FCheckbox(value: _acceptTerms, enabled: !_locked, onChange: (value) => setState(() => _acceptTerms = value), label: const Text('我已阅读并同意用户协议与隐私政策')),
        ],
        if (site.captchaEnabled) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 10, children: [
            Expanded(child: FTextField(control: FTextFieldControl.managed(controller: _captcha), label: const Text('图形验证码'), hint: '输入右侧字符', enabled: !_locked && !_captchaLoading, textInputAction: TextInputAction.done, onSubmit: (_) => _submit(site))),
            SizedBox(width: 124, height: 44, child: FButton.raw(variant: FButtonVariant.outline, semanticsLabel: '刷新图形验证码', onPress: _locked || _captchaLoading ? null : _loadCaptcha, child: _captchaLoading ? const Center(child: FCircularProgress()) : _captchaImage == null ? const Center(child: Icon(FLucideIcons.refreshCw, size: 18)) : ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_captchaImage!, fit: BoxFit.contain)))),
          ]),
          if (_captchaError != null) FAlert(variant: FAlertVariant.destructive, title: const Text('验证码读取失败'), subtitle: Text(_captchaError!)),
          if (needsCode || _mode == AuthMode.register) Text('每次发送邮件或提交后，请重新填写图形验证码。', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
        ],
        if (mailUnavailable) const FAlert(variant: FAlertVariant.destructive, title: Text('邮件服务尚未配置'), subtitle: Text('注册、邮箱验证和找回密码需配置邮件服务，请联系站点管理员。')),
        if (_error != null) FAlert(variant: FAlertVariant.destructive, icon: const Icon(FLucideIcons.circleAlert), title: const Text('操作未完成'), subtitle: Text(_error!)),
        if (_message != null) FAlert(icon: const Icon(FLucideIcons.mailCheck), title: Text(_mode == AuthMode.login && !_verifying ? '账号提示' : '请查看邮箱'), subtitle: Text(_message!)),
        FButton(size: FButtonSizeVariant.lg, prefix: _busy ? const FCircularProgress() : null, suffix: _busy ? null : const Icon(FLucideIcons.arrowRight, size: 18), onPress: _locked || _captchaLoading || mailUnavailable ? null : () => _submit(site), child: Text(_busy ? '正在处理' : submitLabel)),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
          if (_mode == AuthMode.login && !_verifying) ...[
            FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: _locked ? null : () => _changeMode(AuthMode.register, site), child: const Text('注册账号')),
            FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: _locked ? null : () => _changeMode(AuthMode.reset, site), child: const Text('忘记密码')),
            FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: _locked ? null : () => _changeMode(AuthMode.login, site, verify: true), child: const Text('验证已有邮箱')),
          ] else FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: _locked ? null : () => _changeMode(AuthMode.login, site), child: const Text('返回登录')),
        ]),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, children: [
          FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: () => _showAgreement('用户协议', site.terms), child: const Text('用户协议')),
          Text('与', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
          FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, onPress: () => _showAgreement('隐私政策', site.privacy), child: const Text('隐私政策')),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final site = ref.watch(siteProvider);
    final theme = context.theme;
    final dark = theme.colors.brightness == Brightness.dark;
    final logoutWarning = GoRouterState.of(context).extra;
    return FScaffold(
      childPad: false,
      child: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1000 && constraints.maxHeight >= 640;
        return Row(children: [
          if (desktop) Expanded(child: Padding(
            padding: const EdgeInsets.all(28),
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [theme.colors.primary.withValues(alpha: .13), theme.colors.muted, theme.colors.primary.withValues(alpha: .04)])),
              padding: const EdgeInsets.all(44),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(spacing: 10, children: [ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.asset('assets/branding/app-icon.png', width: 34, height: 34, cacheWidth: 68)), Text(site.asData?.value.siteName ?? '未来画布', style: theme.typography.display.lg.copyWith(fontWeight: FontWeight.w600))]),
                Expanded(child: Center(child: Image.asset('assets/branding/studio-image.png', width: 280, height: 280, cacheWidth: 560, fit: BoxFit.contain))),
                Text('让灵感，\n拥有无限可能。', style: theme.typography.display.xl.copyWith(fontSize: 42, height: 1.35, fontWeight: FontWeight.w500, letterSpacing: -1.5)),
                const SizedBox(height: 20),
                Text('从一段想法到一件作品\n在一个安静的空间里，专注于创作。', style: theme.typography.body.md.copyWith(color: theme.colors.mutedForeground, height: 1.8)),
              ]),
            ),
          )),
          Expanded(child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: desktop ? 56 : 24, vertical: 28),
            child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 410), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '返回探索', onPress: _locked ? null : () => context.go('/explore'), child: const Icon(FLucideIcons.arrowLeft, size: 19)),
                const SizedBox(width: 12),
                if (!desktop) ...[ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/branding/app-icon.png', width: 28, height: 28, cacheWidth: 56)), const SizedBox(width: 10), Text(site.asData?.value.siteName ?? '未来画布', style: theme.typography.display.md.copyWith(fontWeight: FontWeight.w600))],
                const Spacer(),
                FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: dark ? '切换浅色主题' : '切换深色主题', onPress: _locked ? null : () => _setTheme(dark ? ThemeMode.light : ThemeMode.dark), child: Icon(dark ? FLucideIcons.sun : FLucideIcons.moon, size: 19)),
              ]),
              SizedBox(height: desktop ? 48 : 32),
              if (logoutWarning is String && logoutWarning.isNotEmpty) ...[
                FAlert(title: const Text('本机已退出登录'), subtitle: Text(logoutWarning)),
                const SizedBox(height: 24),
              ],
              if (logoutWarning is AuthNotice) ...[
                FAlert(title: Text(logoutWarning.title), subtitle: Text(logoutWarning.message)),
                if (logoutWarning.warning != null) ...[const SizedBox(height: 12), FAlert(variant: FAlertVariant.destructive, title: const Text('本机会话清理未完成'), subtitle: Text(logoutWarning.warning!))],
                const SizedBox(height: 24),
              ],
              site.when(data: _form, loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 80), child: Center(child: FCircularProgress(semanticsLabel: '正在读取登录方式'))), error: (error, _) => Column(spacing: 18, children: [FAlert(variant: FAlertVariant.destructive, title: const Text('无法读取站点配置'), subtitle: Text(errorMessage(error))), FButton(variant: FButtonVariant.outline, onPress: () { ref.invalidate(siteProvider); _prepare(); }, child: const Text('重新读取'))])),
            ]))),
          )),
        ]);
      })),
    );
  }
}
