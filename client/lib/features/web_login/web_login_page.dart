import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'web_login_repository.dart';

class WebLoginPage extends ConsumerStatefulWidget {
  const WebLoginPage({super.key});
  @override
  ConsumerState<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends ConsumerState<WebLoginPage> {
  WebLoginPreview? _preview;
  CancelToken? _request;
  String _id = '', _busy = '';
  String? _error;
  bool _scanning = false, _expired = false;
  int _operation = 0;

  void _cancel() {
    _operation++;
    _request?.cancel('页面已关闭');
    if (mounted && _scanning) setState(() => _scanning = false);
  }

  void _back() {
    _cancel();
    context.canPop() ? context.pop() : context.go('/settings');
  }

  @override
  void dispose() {
    _operation++;
    _request?.cancel('页面已关闭');
    super.dispose();
  }

  bool _current(int operation, int epoch, String account) => mounted && operation == _operation && ref.read(apiProvider).epoch == epoch && ref.read(sessionProvider).asData?.value?.id == account && ModalRoute.of(context)?.isCurrent != false;

  void _scan() {
    if (_busy.isNotEmpty || ModalRoute.of(context)?.isCurrent == false) return;
    _request?.cancel('重新扫码');
    _operation++;
    setState(() { _scanning = true; _preview = null; _id = ''; _error = null; _expired = false; });
  }

  void _detected(BarcodeCapture capture) {
    if (!_scanning || _busy.isNotEmpty || ModalRoute.of(context)?.isCurrent == false) return;
    final payload = capture.barcodes.where((code) => code.format == BarcodeFormat.qrCode && code.rawValue != null).firstOrNull?.rawValue;
    if (payload == null) return;
    try {
      _id = appWebLoginId(payload, ref.read(apiProvider).baseUrl);
      _read();
    } catch (error) { setState(() { _scanning = false; _error = errorMessage(error); }); }
  }

  Future<void> _read() async {
    if (_busy.isNotEmpty || _id.isEmpty || ModalRoute.of(context)?.isCurrent == false) return;
    final operation = ++_operation, api = ref.read(apiProvider), epoch = api.epoch;
    final account = ref.read(sessionProvider).asData?.value?.id;
    if (account == null) return;
    final token = CancelToken();
    _request?.cancel('重新读取'); _request = token;
    setState(() { _scanning = false; _busy = 'preview'; _error = null; });
    try {
      final value = await ref.read(webLoginRepositoryProvider).preview(_id, token);
      if (_current(operation, epoch, account)) setState(() { _preview = value; _expired = false; });
    } catch (error) {
      if (_current(operation, epoch, account)) setState(() { _error = errorMessage(error); _expired = error is ApiException && error.status == 410; });
    } finally { if (_current(operation, epoch, account)) setState(() => _busy = ''); }
  }

  Future<void> _decide(String action) async {
    final value = _preview;
    if (_busy.isNotEmpty || value == null || value.status != 'scanned' || _expired) return;
    final operation = ++_operation, api = ref.read(apiProvider), epoch = api.epoch;
    final account = ref.read(sessionProvider).asData?.value?.id;
    if (account == null || ModalRoute.of(context)?.isCurrent == false) return;
    final token = CancelToken();
    _request?.cancel('开始确认'); _request = token;
    setState(() { _busy = action; _error = null; });
    try {
      final status = await ref.read(webLoginRepositoryProvider).decide(value, action, token, checkCurrent: () {
        if (!_current(operation, epoch, account) || token.isCancelled) throw const ApiException('页面或账号已切换，本次操作已取消', canceled: true);
      });
      if (_current(operation, epoch, account)) setState(() => _preview = value.withStatus(status));
    } catch (error) {
      if (_current(operation, epoch, account)) setState(() { _error = errorMessage(error); _expired = error is ApiException && error.status == 410; });
    } finally { if (_current(operation, epoch, account)) setState(() => _busy = ''); }
  }

  Widget _camera() => FCard(clipBehavior: Clip.antiAlias, child: AspectRatio(aspectRatio: 1, child: MobileScanner(
    onDetect: _detected,
    placeholderBuilder: (_) => const StatePanel(title: '正在打开相机', loading: true),
    errorBuilder: (_, error) => ColoredBox(color: context.theme.colors.card, child: StatePanel(
      title: error.errorCode == MobileScannerErrorCode.permissionDenied ? '请允许访问相机' : '相机暂时不可用',
      description: error.errorCode == MobileScannerErrorCode.permissionDenied ? '在系统设置中为未来画布打开相机权限，然后返回重新扫码。' : '请在有相机的手机上重试。',
      icon: FLucideIcons.camera,
    )),
    overlayBuilder: (context, _) => IgnorePointer(child: Center(child: Container(width: 220, height: 220, decoration: BoxDecoration(border: Border.all(color: context.theme.colors.primary, width: 2), borderRadius: BorderRadius.circular(AppRadius.lg))))),
  )));

  Widget _target(String title, String value, {String? description}) => FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.sm, children: [
    Text(title, style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground)),
    SelectableText(value, style: context.theme.typography.display.md.copyWith(fontWeight: FontWeight.w600)),
    if (description != null) SelectableText(description, style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground)),
  ]));

  Widget _confirmation(WebLoginPreview value) {
    final user = ref.watch(sessionProvider).asData?.value;
    final status = _expired ? '二维码已过期，请在登录页面重新生成' : const {'scanned': '等待你确认', 'confirmed': '已确认授权，请返回登录页面查看结果', 'rejected': '已拒绝本次登录', 'consumed': '登录页面已完成登录'}[value.status]!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.lg, children: [
      _target('要登录的站点', value.siteName.isEmpty ? '当前站点' : value.siteName, description: value.origin),
      _target('将使用当前账号', user?.displayName.isNotEmpty == true ? user!.displayName : '当前登录账号', description: user?.email.isNotEmpty == true ? user!.email : null),
      FAlert(icon: Icon(value.status == 'scanned' && !_expired ? FLucideIcons.shieldCheck : FLucideIcons.info), title: Text(status), subtitle: Text(value.status == 'scanned' && !_expired ? '仅确认本人正在使用的网页或桌面客户端。扫描二维码不会自动授权登录，也不会绑定或合并账号。' : value.status == 'rejected' || _expired ? '本次二维码不会获得当前账号的登录授权。' : '登录会话只发送给创建二维码的设备。')),
      if (value.status == 'scanned' && !_expired) Text('二维码有效期为 5 分钟，过期状态以服务器为准。', style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.mutedForeground)),
      if (_error != null) FAlert(variant: FAlertVariant.destructive, title: const Text('登录操作未完成'), subtitle: Text(_error!)),
      if (_error != null && !_expired) FButton(variant: FButtonVariant.outline, onPress: _busy.isEmpty ? _read : null, child: const Text('查询实际登录状态')),
      if (value.status == 'scanned' && !_expired && _error == null) ...[
        FButton(onPress: _busy.isEmpty ? () => _decide('confirm') : null, prefix: _busy == 'confirm' ? const FCircularProgress() : const Icon(FLucideIcons.monitorCheck, size: 18), child: Text(_busy == 'confirm' ? '正在确认' : '确认登录本人正在使用的设备')),
        FButton(variant: FButtonVariant.ghost, onPress: _busy.isEmpty ? () => _decide('reject') : null, child: Text(_busy == 'reject' ? '正在拒绝' : '拒绝本次登录')),
      ],
      if (_busy.isEmpty && (value.status != 'scanned' || _expired)) FButton(variant: FButtonVariant.outline, onPress: _scan, child: const Text('扫描新的二维码')),
    ]);
  }

  Widget _ready(SiteData site) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.lg, children: [
    if (!site.appQrLogin) FAlert(icon: const Icon(FLucideIcons.monitor), title: const Text('当前服务器尚未支持 App 扫码登录'), subtitle: const Text('请联系管理员更新服务后重新读取。原有小程序扫码入口继续使用小程序确认。'))
    else if (_preview != null) _confirmation(_preview!)
    else if (_scanning) ...[_camera(), Text('将相机对准本站网页或桌面客户端的 App 登录二维码', textAlign: TextAlign.center, style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground)), FButton(variant: FButtonVariant.ghost, onPress: () => setState(() => _scanning = false), child: const Text('取消扫码'))]
    else ...[
      FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.lg, children: [
        Icon(FLucideIcons.scanLine, size: 36, color: context.theme.colors.primary),
        Text('在电脑上继续创作', style: context.theme.typography.display.lg.copyWith(fontWeight: FontWeight.w600)),
        Text('1. 在网页或桌面客户端选择「手机 App 扫码」。\n2. 使用手机扫描二维码，核对站点和账号。\n3. 点击确认，让本人使用的设备登录。', style: context.theme.typography.body.sm.copyWith(height: 1.9, color: context.theme.colors.mutedForeground)),
        SelectableText(ref.read(webLoginRepositoryProvider).origin, style: context.theme.typography.body.sm),
      ])),
      if (_error != null) FAlert(variant: FAlertVariant.destructive, title: const Text('扫码未完成'), subtitle: Text(_error!)),
      if (_busy.isNotEmpty) const StatePanel(title: '正在读取网页登录请求', loading: true)
      else FButton(prefix: const Icon(FLucideIcons.scanLine, size: 18), onPress: _scan, child: const Text('开始扫码')),
      if (_id.isNotEmpty && _error != null && !_expired) FButton(variant: FButtonVariant.outline, onPress: _busy.isEmpty ? _read : null, child: const Text('重新读取登录请求')),
    ],
  ]);

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) return StatePanel(title: '请在手机 App 扫码', description: '在网页或桌面客户端打开登录二维码，再使用手机 App 扫描并确认。', icon: FLucideIcons.smartphone, action: FButton(mainAxisSize: MainAxisSize.min, onPress: _back, child: const Text('返回')));
    final site = ref.watch(siteProvider);
    return PopScope(onPopInvokedWithResult: (didPop, _) { if (didPop) _cancel(); }, child: SingleChildScrollView(padding: const EdgeInsets.all(AppSpace.lg), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.lg, children: [
      Row(spacing: AppSpace.sm, children: [FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '返回上一页', onPress: _back, child: const Icon(FLucideIcons.arrowLeft, size: 18)), Expanded(child: Text('扫码登录', style: context.theme.typography.display.lg)), FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '重新读取扫码服务', onPress: _busy.isEmpty && !_scanning ? () => ref.invalidate(siteProvider) : null, child: const Icon(FLucideIcons.refreshCw, size: 18))]),
      if (site.hasError) StatePanel(title: '扫码服务读取失败', description: errorMessage(site.error!), action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(siteProvider), child: const Text('重新读取')))
      else site.when(skipLoadingOnRefresh: false, data: _ready, loading: () => const StatePanel(title: '正在读取扫码服务', loading: true), error: (error, _) => StatePanel(title: '扫码服务读取失败', description: errorMessage(error))),
    ])))));
  }
}
