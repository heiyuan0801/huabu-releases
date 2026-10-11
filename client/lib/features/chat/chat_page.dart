import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';
import 'package:mime/mime.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../channels/channel_providers.dart';
import 'chat_controller.dart';
import 'chat_models.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});
  @override
  Widget build(BuildContext context) => const AccountGate(child: _ChatWorkspace());
}

class _ChatWorkspace extends ConsumerStatefulWidget {
  const _ChatWorkspace();
  @override
  ConsumerState<_ChatWorkspace> createState() => _ChatWorkspaceState();
}

class _ChatWorkspaceState extends ConsumerState<_ChatWorkspace> {
  final _prompt = TextEditingController(), _search = TextEditingController();
  final _scroll = ScrollController();
  final _images = <ChatPickedImage>[];
  String? _modelValue;
  bool _historyOpen = false, _picking = false;
  ChatController? _controller;
  int? _accountEpoch;

  @override
  void dispose() {
    _controller?.stop(epoch: _accountEpoch);
    _prompt.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() action, {String? success}) async {
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    try {
      await action();
      if (mounted && api.epoch == epoch && success != null) toast(context, success);
    } catch (error) {
      if (mounted && api.epoch == epoch && !(error is ApiException && error.canceled)) toast(context, errorMessage(error));
    }
  }

  Future<void> _pickImages() async {
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    setState(() => _picking = true);
    try {
      final files = await openFiles(acceptedTypeGroups: const [XTypeGroup(label: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp'], uniformTypeIdentifiers: ['public.png', 'public.jpeg', 'org.webmproject.webp'], mimeTypes: ['image/png', 'image/jpeg', 'image/webp'])]);
      api.assertEpoch(epoch);
      for (final file in files) {
        if (!mounted) return;
        api.assertEpoch(epoch);
        final bytes = await file.readAsBytes();
        api.assertEpoch(epoch);
        if (!mounted) return;
        final mime = lookupMimeType(file.name, headerBytes: bytes) ?? '';
        if (!['image/png', 'image/jpeg', 'image/webp'].contains(mime)) throw const ApiException('请选择 PNG、JPEG 或 WebP 图片');
        setState(() => _images.add(ChatPickedImage(MediaBytes(bytes: bytes, mimeType: mime), file.name)));
      }
    } catch (error) {
      if (mounted && api.epoch == epoch && !(error is ApiException && error.canceled)) toast(context, errorMessage(error));
    } finally { if (mounted && api.epoch == epoch) setState(() => _picking = false); }
  }

  Future<void> _send(ImageModel? model) async {
    if (model == null || _prompt.text.trim().isEmpty || _picking) return;
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    try {
      final dispatched = await ref.read(chatProvider.notifier).send(_prompt.text, model, List.of(_images));
      if (mounted && api.epoch == epoch && dispatched) setState(() { _prompt.clear(); _images.clear(); });
    } catch (error) {
      if (mounted && api.epoch == epoch && !(error is ApiException && error.canceled)) toast(context, errorMessage(error));
    }
  }

  Future<bool> _confirm(String title, String description, String action) async => await showFDialog<bool>(
    context: context,
    builder: (context, style, animation) => FDialog(style: style, animation: animation, builder: (context, _) => Padding(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.lg, children: [
        Text(title, style: context.theme.typography.display.lg),
        Text(description, style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground)),
        Row(mainAxisAlignment: MainAxisAlignment.end, spacing: AppSpace.sm, children: [
          FButton(mainAxisSize: MainAxisSize.min, variant: FButtonVariant.outline, onPress: () => Navigator.pop(context, false), child: const Text('取消')),
          FButton(mainAxisSize: MainAxisSize.min, variant: FButtonVariant.destructive, onPress: () => Navigator.pop(context, true), child: Text(action)),
        ]),
      ]),
    )),
  ) ?? false;

  Future<void> _delete(ChatSession session) async {
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    if (await _confirm('删除这段对话？', '“${session.title}”及其中的消息将从服务器聊天记录移除。', '删除对话') && mounted && api.epoch == epoch) await _perform(() => ref.read(chatProvider.notifier).deleteSession(session.id), success: '对话已删除');
  }

  Future<void> _reload(ChatState state) async {
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    if (state.dirty && !await _confirm('重新读取服务器记录？', '尚未保存的本次内容会从界面移除，请先复制需要保留的回复。', '重新读取')) return;
    if (mounted && api.epoch == epoch) ref.invalidate(chatProvider);
  }

  @override
  Widget build(BuildContext context) {
    _controller = ref.read(chatProvider.notifier);
    _accountEpoch = ref.read(apiProvider).epoch;
    ref.listen(chatProvider, (previous, next) {
      final changedSession = previous?.asData?.value.activeSessionId != next.asData?.value.activeSessionId;
      if (changedSession && mounted) setState(() { _modelValue = next.asData?.value.active?.model; _prompt.clear(); _images.clear(); });
      final follow = changedSession || !_scroll.hasClients || _scroll.position.extentAfter < 100;
      if (follow) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent); });
    });
    return ref.watch(chatProvider).when(
      loading: () => const StatePanel(title: '正在读取对话', loading: true),
      error: (error, _) => StatePanel(title: '对话读取失败', description: errorMessage(error), icon: FLucideIcons.messageSquareWarning, action: FButton(mainAxisSize: MainAxisSize.min, onPress: () => ref.invalidate(chatProvider), child: const Text('重新读取'))),
      data: (state) => LayoutBuilder(builder: (context, constraints) {
        final wide = AppLayout.isDesktop && constraints.maxWidth >= 760;
        final catalog = ref.watch(catalogProvider);
        final models = (catalog.asData?.value ?? <ImageModel>[]).where((model) => model.capability == 'text' && ['openai', 'gemini'].contains(model.apiFormat)).toList();
        final model = models.where((item) => item.value == (_modelValue ?? state.active?.model)).firstOrNull ?? models.firstOrNull;
        final conversation = Column(children: [
          ConstrainedBox(constraints: BoxConstraints(maxHeight: constraints.maxHeight * .4), child: SingleChildScrollView(child: Column(children: [_header(state, model, models, wide), if (state.dirty) _saveBanner(state)]))),
          Expanded(child: _messages(state)),
          ConstrainedBox(constraints: BoxConstraints(maxHeight: constraints.maxHeight * .55), child: SingleChildScrollView(child: _composer(state, model, catalog, wide, constraints.maxHeight < 500))),
        ]);
        return CallbackShortcuts(bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () { if (!state.busy && !state.dirty) _send(model); },
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): () { if (!state.busy && !state.dirty) _send(model); },
        }, child: wide ? Row(children: [SizedBox(width: 240, child: _history(state, wide)), Expanded(child: conversation)]) : _historyOpen ? _history(state, wide) : conversation);
      }),
    );
  }

  Widget _history(ChatState state, bool wide) {
    final theme = context.theme, query = _search.text.trim().toLowerCase();
    final sessions = state.sessions.where((item) => query.isEmpty || item.title.toLowerCase().contains(query) || item.messages.any((message) => message.content.toLowerCase().contains(query))).toList();
    final enabled = !state.busy && !state.dirty;
    return Container(
      decoration: BoxDecoration(color: theme.colors.card, border: Border(right: BorderSide(color: theme.colors.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Column(spacing: AppSpace.lg, children: [
          Row(children: [Expanded(child: Text('对话历史', style: theme.typography.display.md.copyWith(fontWeight: FontWeight.w600))), if (!wide) FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '返回聊天', onPress: () => setState(() => _historyOpen = false), child: const Icon(FLucideIcons.x, size: 18))]),
          FButton(variant: FButtonVariant.outline, prefix: const Icon(FLucideIcons.plus, size: 17), onPress: enabled ? () => _perform(() => ref.read(chatProvider.notifier).newSession()).then((_) { if (mounted) setState(() => _historyOpen = false); }) : null, child: const Text('新建对话')),
          FTextField(control: FTextFieldControl.managed(controller: _search, onChange: (_) => setState(() {})), hint: '搜索对话', prefixBuilder: (_, _, _) => const Padding(padding: EdgeInsets.only(left: 12, right: 8), child: Icon(FLucideIcons.search, size: 16))),
        ])),
        Expanded(child: sessions.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Text(query.isEmpty ? '还没有对话，写下第一个想法。' : '没有搜索结果，试试其他关键词。', textAlign: TextAlign.center, style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground)))) : ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          itemCount: sessions.length,
          itemBuilder: (context, index) {
            final session = sessions[index], selected = session.id == state.activeSessionId;
            return Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: Row(children: [
              Expanded(child: FButton.raw(variant: selected ? FButtonVariant.secondary : FButtonVariant.ghost, selected: selected, onPress: enabled ? () => _perform(() => ref.read(chatProvider.notifier).selectSession(session.id)).then((_) { if (mounted) setState(() => _historyOpen = false); }) : null, child: Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md), child: Row(spacing: AppSpace.sm, children: [
                Icon(FLucideIcons.messageSquare, size: 16, color: selected ? theme.colors.primary : theme.colors.mutedForeground),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.typography.body.sm), Text('${session.messages.where((message) => message.role == 'user').length} 条消息', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground))])),
              ])))),
              FButton.icon(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, semanticsLabel: '删除对话：${session.title}', onPress: enabled ? () => _delete(session) : null, child: Icon(FLucideIcons.trash2, size: 14, color: theme.colors.mutedForeground)),
            ]));
          },
        )),
        Padding(padding: const EdgeInsets.all(AppSpace.lg), child: FButton(variant: FButtonVariant.ghost, prefix: const Icon(FLucideIcons.refreshCw, size: 15), onPress: state.busy ? null : () => _reload(state), child: const Text('重新读取'))),
      ]),
    );
  }

  Widget _header(ChatState state, ImageModel? model, List<ImageModel> models, bool wide) => Padding(
    padding: EdgeInsets.fromLTRB(wide ? AppSpace.xl : AppSpace.lg, AppSpace.lg, wide ? AppSpace.xl : AppSpace.lg, AppSpace.sm),
    child: LayoutBuilder(builder: (context, constraints) {
      final title = Row(children: [
        if (!wide) ...[FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '对话历史', onPress: () => setState(() => _historyOpen = true), child: const Icon(FLucideIcons.panelLeft, size: 19)), const SizedBox(width: AppSpace.sm)],
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [Text('AI 聊天', style: context.theme.typography.display.lg.copyWith(fontWeight: FontWeight.w600)), Text(state.active?.title ?? '让想法继续生长', maxLines: 1, overflow: TextOverflow.ellipsis, style: context.theme.typography.body.xs.copyWith(color: context.theme.colors.mutedForeground))])),
        if (!wide) FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '新建对话', onPress: state.busy || state.dirty ? null : () => _perform(() => ref.read(chatProvider.notifier).newSession()), child: const Icon(FLucideIcons.plus, size: 19)),
      ]);
      final select = FSelect<String>(items: {for (final item in models) '${item.name} · ${item.providerName}': item.value}, control: FSelectControl.lifted(value: model?.value, onChange: (value) => setState(() => _modelValue = value)), enabled: !state.busy && models.isNotEmpty, hint: '选择聊天模型');
      return constraints.maxWidth >= 550 ? Row(spacing: AppSpace.lg, children: [Expanded(child: title), SizedBox(width: 270, child: select)]) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.md, children: [title, select]);
    }),
  );

  Widget _saveBanner(ChatState state) => Container(
    margin: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
    padding: const EdgeInsets.all(AppSpace.md),
    decoration: BoxDecoration(color: context.theme.colors.secondary, borderRadius: BorderRadius.circular(AppRadius.md)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.sm, children: [
      Text(state.saveError, maxLines: 3, overflow: TextOverflow.ellipsis, style: context.theme.typography.body.sm),
      FButton(mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, variant: FButtonVariant.outline, onPress: state.busy ? null : state.conflict ? () => _reload(state) : () => _perform(() => ref.read(chatProvider.notifier).retrySave(), success: '聊天记录已保存'), child: Text(state.conflict ? '重新读取' : '重试保存')),
    ]),
  );

  Widget _messages(ChatState state) {
    final messages = state.active?.messages ?? <ChatMessage>[];
    if (messages.isEmpty) return LayoutBuilder(builder: (context, constraints) => constraints.maxHeight < 200 ? Center(child: Text('写下你的想法', style: context.theme.typography.body.sm.copyWith(color: context.theme.colors.mutedForeground))) : const StatePanel(title: '从一个想法开始', description: '写作、编程、梳理思路，或结合图片展开讨论。', icon: FLucideIcons.sparkles));
    return ListView.builder(controller: _scroll, padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl), itemCount: messages.length, itemBuilder: (context, index) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 850), child: _MessageView(message: messages[index], receiving: state.busy && index == messages.length - 1 && messages[index].status == 'pending'))));
  }

  Widget _composer(ChatState state, ImageModel? model, AsyncValue<List<ImageModel>> catalog, bool wide, bool compact) {
    final theme = context.theme, enabled = !state.busy && !state.dirty && !_picking && model != null;
    return SafeArea(top: false, child: Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, wide ? AppSpace.xl : AppSpace.md),
      child: Align(alignment: Alignment.bottomCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 850), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.sm, children: [
        if (catalog.isLoading) const Row(mainAxisAlignment: MainAxisAlignment.center, spacing: AppSpace.sm, children: [SizedBox(width: 16, height: 16, child: FCircularProgress()), Text('正在读取聊天模型')]),
        if (catalog.hasError) Row(children: [Expanded(child: Text('模型读取失败：${errorMessage(catalog.error!)}', style: theme.typography.body.xs)), FButton(mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, variant: FButtonVariant.ghost, onPress: () => refreshCatalog(ref), child: const Text('重试'))]),
        for (final issue in ref.watch(catalogIssuesProvider).entries) Row(children: [Expanded(child: Text('${issue.key}读取失败：${issue.value}', style: theme.typography.body.xs)), FButton(mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, variant: FButtonVariant.ghost, onPress: () => refreshCatalog(ref), child: const Text('重试'))]),
        if (!catalog.isLoading && !catalog.hasError && model == null) Row(children: [const Expanded(child: Text('没有可用的聊天模型')), FButton(mainAxisSize: MainAxisSize.min, size: FButtonSizeVariant.sm, variant: FButtonVariant.outline, onPress: () => context.go('/channels'), child: const Text('配置渠道'))]),
        FCard(child: Padding(padding: const EdgeInsets.all(AppSpace.md), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.md, children: [
          if (_images.isNotEmpty) SizedBox(height: 72, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _images.length, separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm), itemBuilder: (context, index) => Stack(children: [
            ClipRRect(borderRadius: BorderRadius.circular(AppRadius.sm), child: Image.memory(_images[index].media.bytes, width: 72, height: 72, fit: BoxFit.cover)),
            Positioned(top: 0, right: 0, child: FButton.icon(size: FButtonSizeVariant.sm, semanticsLabel: '移除附件：${_images[index].name}', onPress: state.busy ? null : () => setState(() => _images.removeAt(index)), child: const Icon(FLucideIcons.x, size: 12))),
          ]))),
          FTextField(control: FTextFieldControl.managed(controller: _prompt, onChange: (_) => setState(() {})), enabled: !state.busy && !state.dirty, minLines: compact ? 1 : 2, maxLines: compact ? 3 : 5, hint: '输入消息，与 AI 一起推进想法…', textInputAction: TextInputAction.newline),
          Row(children: [
            FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '添加图片附件', onPress: enabled ? _pickImages : null, child: _picking ? const SizedBox(width: 18, height: 18, child: FCircularProgress()) : const Icon(FLucideIcons.paperclip, size: 18)),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(_images.isEmpty ? wide ? '⌘ / Ctrl + Enter 发送' : '支持图片附件' : '${_images.length} 张图片 · 识别取决于模型', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground))),
            FButton(mainAxisSize: MainAxisSize.min, onPress: state.busy ? () => ref.read(chatProvider.notifier).stop() : enabled && _prompt.text.trim().isNotEmpty ? () => _send(model) : null, prefix: Icon(state.busy ? FLucideIcons.square : FLucideIcons.arrowUp, size: 16), child: Text(state.busy ? '停止' : '发送')),
          ]),
        ]))),
        if (wide && !compact) Text('对话随账号保存到服务器 · 生成与额度以任务记录为准', textAlign: TextAlign.center, style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
      ]))),
    ));
  }
}

class _MessageView extends ConsumerWidget {
  const _MessageView({required this.message, required this.receiving});
  final ChatMessage message;
  final bool receiving;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.theme, user = message.role == 'user';
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.md, children: [
      if (message.attachments.isNotEmpty) Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [for (final image in message.attachments) ClipRRect(borderRadius: BorderRadius.circular(AppRadius.md), child: SizedBox(width: 120, height: 120, child: ServerImage(image.source)))]),
      if (message.content.isNotEmpty) user ? SelectableText(message.content, style: theme.typography.body.md) : MarkdownBody(
        data: message.content,
        selectable: !receiving,
        styleSheet: MarkdownStyleSheet(
          p: theme.typography.body.md.copyWith(height: 1.7), a: theme.typography.body.md.copyWith(color: theme.colors.primary), code: theme.typography.body.sm.copyWith(fontFamily: 'monospace', backgroundColor: theme.colors.muted),
          h1: theme.typography.display.xl2, h2: theme.typography.display.xl, h3: theme.typography.display.lg, h4: theme.typography.display.md, h5: theme.typography.display.sm, h6: theme.typography.display.sm,
          tableHead: theme.typography.body.sm.copyWith(fontWeight: FontWeight.w600), tableBody: theme.typography.body.sm, tableBorder: TableBorder.all(color: theme.colors.border), tableColumnWidth: const IntrinsicColumnWidth(),
          listBullet: theme.typography.body.md, blockquote: theme.typography.body.md, img: theme.typography.body.md, checkbox: theme.typography.body.md.copyWith(color: theme.colors.primary),
          blockquoteDecoration: BoxDecoration(color: theme.colors.muted, border: Border(left: BorderSide(color: theme.colors.primary, width: 3))), codeblockDecoration: const BoxDecoration(), codeblockPadding: EdgeInsets.zero, horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: theme.colors.border))),
        ),
        builders: {'pre': _CodeBuilder(ref)},
        imageBuilder: (uri, title, alt) => ConstrainedBox(constraints: const BoxConstraints(maxHeight: 320), child: ServerImage(uri.toString(), fit: BoxFit.contain)),
        onTapLink: (_, href, _) { if (href != null) _openLink(context, ref, href); },
      ),
      if (receiving && message.content.isEmpty) const Row(spacing: AppSpace.sm, children: [SizedBox(width: 16, height: 16, child: FCircularProgress()), Text('正在思考…')]),
      if (!receiving && message.status == 'pending') Text('这条回复没有已确认的完成记录，请在任务记录核对。', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground)),
      if (message.notice.isNotEmpty) Text(message.notice, style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground)),
    ]);
    return Padding(padding: const EdgeInsets.only(bottom: AppSpace.xxl), child: user ? Align(alignment: Alignment.centerRight, child: Container(constraints: const BoxConstraints(maxWidth: 680), padding: const EdgeInsets.all(AppSpace.lg), decoration: BoxDecoration(color: theme.colors.secondary, borderRadius: BorderRadius.circular(AppRadius.lg)), child: body)) : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.md, children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(color: theme.colors.primary.withValues(alpha: .12), borderRadius: BorderRadius.circular(AppRadius.sm)), child: Icon(FLucideIcons.sparkles, size: 16, color: theme.colors.primary)),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.md, children: [
        Text(message.modelName.isEmpty ? 'AI 助手' : message.modelName, style: theme.typography.body.sm.copyWith(fontWeight: FontWeight.w600)),
        body,
        if (!receiving) Row(spacing: AppSpace.xs, children: [
          if (message.content.isNotEmpty) FButton.icon(size: FButtonSizeVariant.sm, variant: FButtonVariant.ghost, semanticsLabel: '复制回复', onPress: () => copyText(context, ref, message.content), child: const Icon(FLucideIcons.copy, size: 14)),
          if (message.runId.isNotEmpty) FButton(size: FButtonSizeVariant.sm, variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: () => context.go('/tasks'), child: const Text('任务记录')),
        ]),
      ])),
    ]));
  }

  Future<void> _openLink(BuildContext context, WidgetRef ref, String value) async {
    final api = ref.read(apiProvider), epoch = ref.read(apiProvider).epoch;
    final uri = Uri.tryParse(value);
    if (uri == null || !['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) {
      await copyText(context, ref, value);
      return;
    }
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) { /* Offer the same copy action when the platform refuses a link. */ }
    if (context.mounted && api.epoch == epoch) showFToast(context: context, title: const Text('链接无法打开'), suffixBuilder: (_, _) => FButton(variant: FButtonVariant.ghost, size: FButtonSizeVariant.sm, onPress: () => copyText(context, ref, value), child: const Text('复制链接')));
  }
}

class _CodeBuilder extends MarkdownElementBuilder {
  _CodeBuilder(this.ref);
  final WidgetRef ref;
  @override
  bool isBlockElement() => true;
  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    final theme = context.theme;
    final child = element.children?.whereType<md.Element>().firstOrNull;
    final language = child?.attributes['class']?.replaceFirst('language-', '') ?? '';
    final text = element.textContent;
    return Container(clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: theme.colors.muted, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: theme.colors.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs), child: Row(children: [Expanded(child: Text(language.isEmpty ? '代码' : language, style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground))), FButton(size: FButtonSizeVariant.sm, variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.copy, size: 13), onPress: () => copyText(context, ref, text), child: const Text('复制'))])),
      SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.lg), child: SelectableText(text, style: theme.typography.body.sm.copyWith(fontFamily: 'monospace', height: 1.6))),
    ]));
  }
}
