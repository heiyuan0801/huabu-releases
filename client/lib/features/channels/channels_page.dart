import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'channel_providers.dart';

ImageModel _channelModel(LocalChannel channel) => ImageModel(id: 'local:${channel.id}', providerId: 'local:${channel.id}', providerName: channel.name, model: '', displayName: '', apiFormat: channel.apiFormat, capability: 'text', creditCost: 0, value: 'local:${channel.id}');

class ChannelsPage extends ConsumerStatefulWidget {
  const ChannelsPage({super.key});
  @override
  ConsumerState<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends ConsumerState<ChannelsPage> {
  String _tab = 'local', _busy = '';
  String? _error;

  Future<void> _edit([LocalChannel? channel]) async {
    if (_busy.isNotEmpty) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final result = await showFDialog<bool>(context: context, barrierDismissible: false, builder: (context, style, animation) => _ChannelEditor(initial: channel, style: style, animation: animation));
    if (mounted && api.epoch == epoch && result == true) toast(context, '个人渠道已保存到本设备');
  }

  Future<void> _action(LocalChannel channel, String type, Future<void> Function() action) async {
    if (_busy.isNotEmpty) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    setState(() { _busy = '${channel.id}:$type'; _error = null; });
    try {
      await action();
    } catch (error) {
      if (mounted && api.epoch == epoch) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted && api.epoch == epoch) setState(() => _busy = '');
    }
  }

  Future<void> _test(LocalChannel channel) => _action(channel, 'test', () async {
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final models = await ModelApiTarget(api, _channelModel(channel), channel: channel).fetchModels();
    if (mounted && api.epoch == epoch) toast(context, '模型目录可读取，共 ${models.length} 个模型');
  });

  Future<void> _remove(LocalChannel channel) async {
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final confirmed = await showFDialog<bool>(context: context, builder: (context, style, animation) => FDialog(style: style, animation: animation, builder: (context, style) => Padding(padding: const EdgeInsets.all(AppSpace.xl), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 20, children: [
      Text('删除「${channel.name}」？', style: style.titleTextStyle),
      const Text('将删除此设备上的渠道配置和对应 API Key。'),
      Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 12, children: [FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, onPress: () => Navigator.pop(context, false), child: const Text('取消')), FButton(variant: FButtonVariant.destructive, mainAxisSize: MainAxisSize.min, onPress: () => Navigator.pop(context, true), child: const Text('删除渠道'))]),
    ]))));
    if (confirmed == true && mounted && api.epoch == epoch) await _action(channel, 'remove', () => ref.read(localChannelsProvider.notifier).remove(channel.id));
  }

  Widget _personal(List<LocalChannel> channels) {
    if (channels.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: StatePanel(title: '连接你自己的 AI 接口', description: '添加接口地址与密钥，再读取模型目录。\n配置与密钥仅保存在本设备，按登录账号隔离。', icon: FLucideIcons.plug));
    final theme = context.theme;
    return Column(spacing: AppSpace.lg, children: [for (final channel in channels) FCard(child: Padding(padding: const EdgeInsets.all(AppSpace.xl), child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 18, children: [
      Row(spacing: 14, children: [Icon(FLucideIcons.plug, color: AppTheme.accent, size: 24), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 5, children: [Text(channel.name, style: theme.typography.display.md.copyWith(fontWeight: FontWeight.w600)), Text('${channel.apiFormat.toUpperCase()} · ${channel.models.length} 个已配置模型', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground))])), FSwitch(value: channel.enabled, enabled: _busy.isEmpty, semanticsLabel: '启用${channel.name}', onChange: (enabled) => _action(channel, 'enable', () => ref.read(localChannelsProvider.notifier).setEnabled(channel, enabled)))]),
      SelectableText(channel.baseUrl, style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground)),
      Wrap(spacing: 10, runSpacing: 10, children: [
        FButton(variant: FButtonVariant.outline, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: _busy == '${channel.id}:test' ? const FCircularProgress() : const Icon(FLucideIcons.network, size: 15), onPress: _busy.isEmpty ? () => _test(channel) : null, child: const Text('测试模型目录')),
        FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.settings2, size: 15), onPress: _busy.isEmpty ? () => _edit(channel) : null, child: const Text('编辑渠道')),
        FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.trash2, size: 15), onPress: _busy.isEmpty ? () => _remove(channel) : null, child: const Text('删除')),
      ]),
    ])))]);
  }

  Widget _cloud(List<ImageModel> models) {
    final providers = <String, List<ImageModel>>{};
    for (final model in models) { providers.putIfAbsent(model.providerId, () => []).add(model); }
    if (providers.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: StatePanel(title: '平台暂无已启用渠道', description: '管理员启用渠道及模型后，会出现在这里。', icon: FLucideIcons.cloud));
    final theme = context.theme;
    return Column(spacing: AppSpace.lg, children: [for (final list in providers.values) FCard(child: Padding(padding: const EdgeInsets.all(AppSpace.xl), child: Row(spacing: 16, children: [Icon(FLucideIcons.cloud, size: 25, color: AppTheme.accent), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [Text(list.first.providerName, style: theme.typography.display.md.copyWith(fontWeight: FontWeight.w600)), Text('${list.length} 个可用模型 · ${list.map((model) => model.apiFormat.toUpperCase()).toSet().join(' / ')}', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground))])), Text('已启用', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground))])))]);
  }

  @override
  Widget build(BuildContext context) {
    final localState = ref.watch(localChannelsProvider), cloudState = ref.watch(cloudCatalogProvider), theme = context.theme;
    final local = localState.hasError ? AsyncError<List<LocalChannel>>(localState.error!, localState.stackTrace!) : localState;
    final cloud = cloudState.hasError ? AsyncError<List<ImageModel>>(cloudState.error!, cloudState.stackTrace!) : cloudState;
    return SingleChildScrollView(padding: EdgeInsets.all(AppLayout.isDesktop ? AppSpace.xxl : AppSpace.lg), child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.xl, children: [
      Row(spacing: 12, children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [Text('渠道设置', style: theme.typography.display.xl2), Text('连接模型，让创作自由流动。', style: theme.typography.body.md.copyWith(color: theme.colors.mutedForeground))])), if (_tab == 'local') FButton(mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.plus, size: 18), onPress: local.hasValue && _busy.isEmpty ? () => _edit() : null, child: const Text('添加渠道'))]),
      Wrap(spacing: 8, children: [for (final entry in const {'local': '个人渠道 · 本设备', 'cloud': '平台渠道'}.entries) FButton(variant: _tab == entry.key ? FButtonVariant.secondary : FButtonVariant.ghost, selected: _tab == entry.key, mainAxisSize: MainAxisSize.min, onPress: () => setState(() => _tab = entry.key), child: Text(entry.value))]),
      if (_error != null) FAlert(variant: FAlertVariant.destructive, title: const Text('渠道操作未完成'), subtitle: Text(_error!)),
      if (_tab == 'local') ...[
        FAlert(icon: const Icon(FLucideIcons.shieldCheck), title: const Text('本机配置，安全保存'), subtitle: const Text('接口地址、模型与 API Key 保存在系统安全存储，按账号隔离。请求通过项目服务器代理转发；个人接口由渠道提供方计费。')),
        local.when(skipLoadingOnRefresh: false, data: _personal, loading: () => const StatePanel(title: '正在读取个人渠道', loading: true), error: (error, _) => StatePanel(title: '个人渠道读取失败', description: errorMessage(error), action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => refreshCatalog(ref), child: const Text('重新读取')))),
      ] else ...[
        Text('平台渠道与密钥由管理员维护，以下为当前账号可用的模型目录。', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground)),
        cloud.when(skipLoadingOnRefresh: false, data: _cloud, loading: () => const StatePanel(title: '正在读取平台渠道', loading: true), error: (error, _) => StatePanel(title: '平台渠道读取失败', description: errorMessage(error), action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => refreshCatalog(ref), child: const Text('重新读取')))),
      ],
    ]));
  }
}

class _ChannelEditor extends ConsumerStatefulWidget {
  const _ChannelEditor({this.initial, required this.style, required this.animation});
  final LocalChannel? initial;
  final FDialogStyle style;
  final Animation<double> animation;
  @override
  ConsumerState<_ChannelEditor> createState() => _ChannelEditorState();
}

class _ChannelEditorState extends ConsumerState<_ChannelEditor> {
  final _name = TextEditingController(), _url = TextEditingController(), _key = TextEditingController(), _manual = TextEditingController();
  final _cancel = CancelToken();
  late final int _epoch;
  late final String _id;
  String _format = 'openai';
  bool _saving = false, _loading = false;
  List<String>? _available;
  TextEditingValue _modelSearch = TextEditingValue.empty;
  final _selected = <String, String>{};
  String? _error;
  static const _capabilities = {'文本': 'text', '图片': 'image', '视频': 'video', '音频': 'audio'};

  @override
  void initState() {
    super.initState();
    _epoch = ref.read(apiProvider).epoch;
    final initial = widget.initial;
    _id = initial?.id ?? const Uuid().v4();
    _name.text = initial?.name ?? '';
    _url.text = initial?.baseUrl ?? '';
    _format = initial?.apiFormat ?? 'openai';
    for (final entry in initial?.models ?? <Json>[]) { _selected[jsonString(entry['name'])] = jsonString(entry['capability']); }
  }

  @override
  void dispose() {
    _cancel.cancel('渠道编辑已关闭');
    for (final controller in [_name, _url, _key, _manual]) { controller.dispose(); }
    super.dispose();
  }

  LocalChannel _draft() => LocalChannel(id: _id, name: _name.text.trim(), baseUrl: _url.text.trim(), apiKey: _key.text.trim().isEmpty ? widget.initial?.apiKey ?? '' : _key.text.trim(), apiFormat: _format, enabled: widget.initial?.enabled ?? true, models: [for (final entry in _selected.entries) {'name': entry.key, 'capability': entry.value}]);

  Future<void> _fetch() async {
    if (_loading || _saving) return;
    setState(() { _loading = true; _error = null; });
    try {
      final channel = _draft();
      ModelApiTarget.validateBase(channel.baseUrl);
      if (channel.apiKey.isEmpty) throw const ApiException('读取模型前请填写 API Key');
      final names = await ModelApiTarget(ref.read(apiProvider), _channelModel(channel), channel: channel).fetchModels(cancelToken: _cancel);
      if (mounted && ref.read(apiProvider).epoch == _epoch) setState(() => _available = names);
    } catch (error) {
      if (mounted && ref.read(apiProvider).epoch == _epoch) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    final api = ref.read(apiProvider);
    if (api.epoch != _epoch) { Navigator.pop(context, false); return; }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(localChannelsProvider.notifier).save(_draft());
      if (mounted && api.epoch == _epoch) Navigator.pop(context, true);
    } catch (error) {
      if (mounted && api.epoch == _epoch) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider.select((session) => session.asData?.value?.id), (previous, next) { if (previous != next && mounted) Navigator.pop(context, false); });
    final locked = _saving || _loading;
    final names = {..._selected.keys, ...?_available}.where((name) => name.toLowerCase().contains(_modelSearch.text.trim().toLowerCase())).toList();
    return PopScope(canPop: !_saving, child: FDialog(style: widget.style, animation: widget.animation, constraints: const BoxConstraints(minWidth: 280, maxWidth: 620), builder: (context, style) => Padding(padding: const EdgeInsets.all(AppSpace.xl), child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .8), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 18, children: [
      Text(widget.initial == null ? '添加个人渠道' : '编辑个人渠道', style: style.titleTextStyle),
      FTextField(control: FTextFieldControl.managed(controller: _name), label: const Text('渠道名称'), hint: '为自己的接口起个名字', enabled: !locked),
      FSelect(items: const {'OpenAI 兼容': 'openai', 'Gemini 原生': 'gemini', '火山方舟 Ark': 'ark'}, control: FSelectControl.lifted(value: _format, onChange: (value) { if (value != null) setState(() { _format = value; _available = null; }); }), label: const Text('接口协议'), enabled: !locked),
      FTextField(control: FTextFieldControl.managed(controller: _url), label: const Text('API Base URL'), hint: _format == 'gemini' ? 'https://generativelanguage.googleapis.com' : _format == 'ark' ? 'https://ark.cn-beijing.volces.com/api/v3' : 'https://api.example.com', keyboardType: TextInputType.url, enabled: !locked, autocorrect: false),
      FTextField.password(control: FTextFieldControl.managed(controller: _key), label: const Text('API Key'), hint: widget.initial?.apiKey.isNotEmpty == true ? '留空保留已保存的密钥' : '输入渠道密钥', enabled: !locked, autofillHints: const []),
      const FDivider(),
      Row(children: [Expanded(child: Text('选择模型与能力', style: context.theme.typography.display.md)), FButton(variant: FButtonVariant.outline, size: FButtonSizeVariant.sm, mainAxisSize: MainAxisSize.min, prefix: _loading ? const FCircularProgress() : const Icon(FLucideIcons.refreshCw, size: 15), onPress: locked ? null : _fetch, child: Text(_loading ? '读取中' : '读取模型'))]),
      Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 10, children: [Expanded(child: FTextField(control: FTextFieldControl.managed(controller: _manual), label: const Text('模型标识'), hint: '也可手动添加完整模型名', enabled: !locked)), FButton.icon(semanticsLabel: '添加模型', onPress: locked ? null : () { final name = _manual.text.trim(); if (name.isNotEmpty) setState(() { _selected.putIfAbsent(name, () => 'text'); _manual.clear(); }); }, child: const Icon(FLucideIcons.plus, size: 18))]),
      if (_available != null && _available!.isEmpty) const FAlert(title: Text('该渠道返回空模型列表')),
      if (_selected.isNotEmpty || _available?.isNotEmpty == true) ...[
        FTextField(control: FTextFieldControl.lifted(value: _modelSearch, onChange: (value) => setState(() => _modelSearch = value)), hint: '搜索渠道中的模型', enabled: !locked, prefixBuilder: (_, _, _) => const Padding(padding: EdgeInsets.only(left: 12, right: 8), child: Icon(FLucideIcons.search, size: 16))),
        Text('已选择 ${_selected.length} 个模型', style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground)),
        if (names.isEmpty) const Text('没有匹配的模型') else SizedBox(height: MediaQuery.sizeOf(context).height * .3, child: ListView.separated(
          primary: false, itemCount: names.length, separatorBuilder: (_, _) => const SizedBox(height: AppSpace.md),
          itemBuilder: (context, index) {
            final name = names[index];
            return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.md, children: [Expanded(child: FCheckbox(value: _selected.containsKey(name), enabled: !locked, label: Text(name), onChange: (selected) => setState(() { if (selected) { _selected[name] = 'text'; } else { _selected.remove(name); } }))), if (_selected.containsKey(name)) SizedBox(width: 115, child: FSelect(items: _capabilities, control: FSelectControl.lifted(value: _selected[name], onChange: (value) { if (value != null) setState(() => _selected[name] = value); }), enabled: !locked))]);
          },
        )),
      ],
      if (_selected.isEmpty && _available == null) Text('读取真实模型列表或手动添加，再指定对应能力。', style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground)),
      if (_error != null) FAlert(variant: FAlertVariant.destructive, title: const Text('渠道尚未保存'), subtitle: Text(_error!)),
      Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: [FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, onPress: _saving ? null : () => Navigator.pop(context, false), child: const Text('取消')), FButton(mainAxisSize: MainAxisSize.min, prefix: _saving ? const FCircularProgress() : null, onPress: locked ? null : _save, child: Text(_saving ? '正在保存' : '保存渠道'))]),
    ]))))));
  }
}
