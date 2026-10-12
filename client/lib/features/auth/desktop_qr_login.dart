import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/providers.dart';
import 'desktop_qr_repository.dart';

class DesktopQrLogin extends ConsumerStatefulWidget {
  const DesktopQrLogin({super.key, required this.mode, required this.onLoggedIn, required this.onBusyChange});
  final DesktopQrMode mode;
  final VoidCallback onLoggedIn;
  final ValueChanged<bool> onBusyChange;
  @override
  ConsumerState<DesktopQrLogin> createState() => _DesktopQrLoginState();
}

class _DesktopQrLoginState extends ConsumerState<DesktopQrLogin> with WidgetsBindingObserver {
  late final ApiClient _api = ref.read(apiProvider);
  late final DesktopQrRepository _repository = DesktopQrRepository(_api);
  CancelToken _token = CancelToken();
  Timer? _timer;
  DesktopQrChallenge? _challenge;
  String _phase = 'loading', _id = '';
  String? _error;
  int _operation = 0, _epoch = 0;
  bool _consuming = false;

  bool _current(int operation) => mounted && operation == _operation && !_token.isCancelled && _api.epoch == _epoch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _create();
  }

  @override
  void didUpdateWidget(covariant DesktopQrLogin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) _create();
  }

  void _cancel() {
    _operation++;
    _timer?.cancel();
    _token.cancel('扫码登录入口已关闭');
    final id = _id;
    _id = '';
    if (id.isNotEmpty && _api.epoch == _epoch) unawaited(_repository.cancel(id).catchError((Object _) {}));
  }

  void _stop(String phase, [String? error]) {
    _cancel();
    if (mounted) setState(() { _phase = phase; _error = error; });
  }

  Future<void> _create() async {
    _cancel();
    _token = CancelToken();
    final operation = _operation;
    setState(() { _challenge = null; _phase = 'loading'; _error = null; });
    try {
      final user = await ref.read(sessionProvider.future);
      if (!mounted || operation != _operation) return;
      _epoch = _api.epoch;
      if (user != null) { _stop('error', '当前客户端已经登录，请返回创作空间'); return; }
      final site = await ref.read(siteProvider.future);
      if (!_current(operation)) return;
      if (widget.mode == DesktopQrMode.app ? !site.appQrLogin : !site.wechatLogin) throw const ApiException('当前服务器尚未启用此扫码方式，请使用账号登录');
      final value = await _repository.create(widget.mode, _token);
      if (!_current(operation)) { if (_api.epoch == _epoch) unawaited(_repository.cancel(value.id).catchError((Object _) {})); return; }
      _id = value.id;
      setState(() { _challenge = value; _phase = 'pending'; });
      _schedule(operation);
    } catch (error) {
      if (mounted && operation == _operation && !_token.isCancelled && !(error is ApiException && error.canceled)) _stop('error', errorMessage(error));
    }
  }

  void _schedule(int operation) => _timer = Timer(const Duration(seconds: 2), () => _poll(operation));

  Future<void> _poll(int operation) async {
    if (!_current(operation) || _challenge == null) return;
    try {
      final phase = await _repository.status(_challenge!, _token);
      if (!_current(operation)) return;
      if (phase == 'confirmed') {
        _consuming = true;
        widget.onBusyChange(true);
        setState(() => _phase = 'consuming');
        await ref.read(sessionProvider.notifier).loginWithQr(_challenge!.id, cancelToken: _token);
        if (!mounted || operation != _operation) return;
        _id = '';
        if (ref.read(sessionProvider).asData?.value == null) throw const ApiException('扫码登录结果尚未确认，请返回账号登录核对');
        widget.onLoggedIn();
        return;
      }
      if (phase == 'rejected' || phase == 'consumed') { _stop(phase); return; }
      setState(() => _phase = phase);
      _schedule(operation);
    } catch (error) {
      if (mounted && operation == _operation && !(error is ApiException && error.canceled)) _stop(error is ApiException && error.status == 410 ? 'expired' : 'error', _consuming ? '登录尚未完成：${errorMessage(error)}。不会重复提交此二维码，请返回账号登录核对。' : errorMessage(error));
    } finally {
      if (_consuming) { _consuming = false; if (mounted) widget.onBusyChange(false); }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.hidden || state == AppLifecycleState.paused) && !_consuming) _stop('error', '窗口已隐藏，本次二维码已取消，请重新生成');
  }

  @override
  void dispose() {
    _cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((value) => value.asData?.value?.id), (previous, next) { if (previous != next && !_consuming) _stop('error', '账号状态已变更，请返回创作空间或重新生成二维码'); });
    final theme = context.theme, app = widget.mode == DesktopQrMode.app;
    final terminal = ['expired', 'rejected', 'consumed', 'error'].contains(_phase);
    final label = switch (_phase) {
      'loading' => '正在生成登录二维码',
      'pending' => app ? '打开手机 App，点击「扫码登录」' : '打开微信小程序，扫码登录',
      'scanned' => app ? '已扫码，请在手机 App 确认登录' : '已扫码，请在小程序确认登录',
      'consuming' => '正在安全保存登录会话',
      'expired' => '二维码已过期',
      'rejected' => '已取消本次登录',
      'consumed' => '二维码已使用，请核对当前登录状态',
      _ => '扫码登录尚未完成',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
      Center(child: Container(
        width: 248, height: 248,
        decoration: BoxDecoration(color: terminal || _challenge == null ? theme.colors.muted : const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(20), border: Border.all(color: theme.colors.border)),
        padding: const EdgeInsets.all(12),
        child: _challenge == null || terminal || _phase == 'consuming'
          ? Center(child: _phase == 'loading' || _phase == 'consuming' ? FCircularProgress(semanticsLabel: label) : Icon(FLucideIcons.qrCode, size: 46, color: theme.colors.mutedForeground))
          : Opacity(opacity: _phase == 'scanned' ? .35 : 1, child: QrImageView(data: _challenge!.value, size: 224, backgroundColor: const Color(0xFFFFFFFF), semanticsLabel: '仅用于本次客户端登录的二维码')),
      )),
      Text(label, textAlign: TextAlign.center, style: theme.typography.body.md),
      if (!terminal) Text('二维码 5 分钟内有效，扫码后需在${app ? '手机 App' : '小程序'}确认。\n登录账号与扫码设备一致，共用作品与积分。', textAlign: TextAlign.center, style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground, height: 1.7)),
      if (_error != null) FAlert(variant: FAlertVariant.destructive, title: const Text('请核对登录状态'), subtitle: Text(_error!)),
      if (terminal) FButton(variant: FButtonVariant.outline, onPress: _create, child: const Text('重新生成二维码')),
    ]);
  }
}
