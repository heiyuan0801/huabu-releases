import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../updates/update_widgets.dart';
import 'affiliate_providers.dart';

class AffiliatePage extends StatelessWidget {
  const AffiliatePage({super.key});
  @override
  Widget build(BuildContext context) => const AccountGate(child: _AffiliateContent());
}

class _AffiliateContent extends ConsumerStatefulWidget {
  const _AffiliateContent();
  @override
  ConsumerState<_AffiliateContent> createState() => _AffiliateContentState();
}

class _AffiliateContentState extends ConsumerState<_AffiliateContent> {
  AffiliateRecordKind _kind = AffiliateRecordKind.referrals;
  int _page = 1;

  void _refresh() {
    ref.invalidate(affiliateOverviewProvider);
    ref.invalidate(affiliateRecordsProvider((kind: _kind, page: _page)));
  }

  Widget _failure(String title, Object error, VoidCallback retry) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.md, children: [
    FAlert(variant: FAlertVariant.destructive, title: Text(title), subtitle: Text(errorMessage(error))),
    FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, onPress: retry, child: const Text('重新读取')),
  ]);

  Widget _overview(AffiliateOverview value) {
    final theme = context.theme, program = value.program;
    final link = affiliateLink(ref.read(apiProvider).baseUrl, value.code);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.xl, children: [
      LayoutBuilder(builder: (context, bounds) {
        final columns = bounds.maxWidth >= 760 ? 4 : bounds.maxWidth >= 340 ? 2 : 1;
        final width = (bounds.maxWidth - AppSpace.md * (columns - 1)) / columns;
        return Wrap(spacing: AppSpace.md, runSpacing: AppSpace.md, children: [
          for (final entry in {'registered': '邀请注册', 'verified': '完成邮箱验证', 'inviteCredits': '验证奖励积分', 'commissionCredits': '充值分成积分'}.entries)
            SizedBox(width: width, child: FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.sm, children: [
              Text(entry.value, style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground)),
              Text('${value.stats[entry.key]}', style: theme.typography.display.xl.copyWith(fontWeight: FontWeight.w600)),
            ]))),
        ]);
      }),
      FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.lg, children: [
        Wrap(spacing: AppSpace.md, runSpacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('我的邀请链接', style: theme.typography.display.md.copyWith(fontWeight: FontWeight.w600)),
          FBadge(variant: program.enabled ? FBadgeVariant.secondary : FBadgeVariant.outline, child: Text(program.enabled ? '活动已开启' : '活动未开启')),
        ]),
        SelectableText(link, style: theme.typography.body.sm),
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          FButton(mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.link, size: 16), onPress: program.enabled ? () => copyText(context, ref, link) : null, child: const Text('复制邀请链接')),
          FButton(variant: FButtonVariant.outline, mainAxisSize: MainAxisSize.min, prefix: const Icon(FLucideIcons.copy, size: 16), onPress: program.enabled ? () => copyText(context, ref, value.code) : null, child: const Text('复制邀请码')),
        ]),
        Text('邀请码：${value.code}', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
        const FDivider(),
        Text(program.enabled ? '好友通过邀请注册并完成邮箱验证后，你获得 ${program.inviterGrant} 积分，好友额外获得 ${program.inviteeGrant} 积分。' : '管理员开启邀请活动后，新注册用户才会绑定邀请关系。', style: theme.typography.body.sm),
        Text(program.enabled && program.commissionEnabled ? '好友${program.commissionMode == 'first' ? '首笔' : '每笔'}确认到账的充值，按套餐额度的 ${program.commissionRateBps / 100}% 增加你的积分，不足 1 点的部分舍去。' : '当前未开启新的充值返佣。', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground)),
        Text('邀请关系只在新账号注册时绑定，已有账号不能补绑。注册奖励按注册时规则、充值分成按下单时规则结算，实际到账以服务器记录为准。', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground, height: 1.7)),
      ])),
      FAlert(icon: const Icon(FLucideIcons.download), title: const Text('邀请下载，一起创作'), subtitle: const Text('好友下载安装软件后，可在注册页填写你的邀请码。邀请活动开启时，积分在注册并完成邮箱验证后发放；仅下载或安装不会单独触发奖励。')),
      const ReleaseDownloads(),
    ]);
  }

  String _date(Object? value) {
    if (value == null) return '尚未验证';
    final date = DateTime.parse(value as String).toLocal();
    final locale = MaterialLocalizations.of(context);
    return '${locale.formatMediumDate(date)} ${locale.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true)}';
  }

  Widget _records(AffiliateRecords value) {
    final theme = context.theme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.lg, children: [
      if (value.items.isEmpty) StatePanel(title: _kind == AffiliateRecordKind.referrals ? '还没有邀请记录' : '还没有已结算收益', description: _kind == AffiliateRecordKind.referrals ? '分享链接，邀请好友注册并验证邮箱。' : '奖励确认到账后，会显示在这里。', icon: FLucideIcons.gift),
      for (final item in value.items) Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.sm, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.md, children: [
          Expanded(child: Text(jsonString(item['inviteeName']), style: theme.typography.body.md.copyWith(fontWeight: FontWeight.w500))),
          if (_kind == AffiliateRecordKind.earnings) Text('+${item['amount']} 积分', style: theme.typography.body.sm.copyWith(color: theme.colors.primary, fontWeight: FontWeight.w600)),
        ]),
        if (_kind == AffiliateRecordKind.referrals) ...[
          Wrap(spacing: AppSpace.lg, runSpacing: AppSpace.sm, children: [
            Text('账号：${{'active': '正常', 'pending': '待验证', 'disabled': '已禁用', 'deleted': '已注销'}[item['status']] ?? item['status']}', style: theme.typography.body.sm),
            Text('邮箱验证：${_date(item['activatedAt'])}', style: theme.typography.body.sm),
            Text('返佣关系：${item['enabled'] == true ? '正常' : '已暂停'}', style: theme.typography.body.sm),
          ]),
        ] else ...[
          Text({'invite_reward': '邀请验证奖励', 'signup_bonus': '新用户额外奖励', 'recharge_commission': '充值额度分成'}[item['kind']] ?? jsonString(item['kind']), style: theme.typography.body.sm),
          if (item['kind'] == 'recharge_commission') Text('分成比例：${jsonInt(item['rateBps']) / 100}%', style: theme.typography.body.sm),
        ],
        Text('${_kind == AffiliateRecordKind.referrals ? '邀请' : '到账'}时间：${_date(item['createdAt'])}', style: theme.typography.body.xs.copyWith(color: theme.colors.mutedForeground)),
        const FDivider(),
      ]),
      if (_page > 1 || value.total > 10) Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.lg, runSpacing: AppSpace.sm, children: [
        FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: _page > 1 ? () => setState(() => _page--) : null, child: const Text('上一页')),
        Text('第 $_page 页 · 共 ${value.total} 条', style: theme.typography.body.sm),
        FButton(variant: FButtonVariant.ghost, mainAxisSize: MainAxisSize.min, onPress: _page * 10 < value.total ? () => setState(() => _page++) : null, child: const Text('下一页')),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme, overview = ref.watch(affiliateOverviewProvider);
    final query = (kind: _kind, page: _page), records = ref.watch(affiliateRecordsProvider((kind: _kind, page: _page)));
    return SingleChildScrollView(padding: EdgeInsets.all(AppLayout.isDesktop ? AppSpace.xxl : AppSpace.lg), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1080), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.xl, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.md, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: AppSpace.sm, children: [Text('邀请好友，一起创作', style: theme.typography.display.xl2), Text('分享你的邀请链接，查看真实奖励与到账记录。', style: theme.typography.body.sm.copyWith(color: theme.colors.mutedForeground))])),
        FButton.icon(variant: FButtonVariant.ghost, semanticsLabel: '刷新邀请信息', onPress: overview.isLoading || records.isLoading ? null : _refresh, child: const Icon(FLucideIcons.refreshCw, size: 18)),
      ]),
      if (overview.hasError) _failure('邀请信息读取失败', overview.error!, () => ref.invalidate(affiliateOverviewProvider))
      else overview.when(skipLoadingOnRefresh: false, data: _overview, loading: () => const StatePanel(title: '正在读取邀请信息', loading: true), error: (error, _) => _failure('邀请信息读取失败', error, () => ref.invalidate(affiliateOverviewProvider))),
      FCard(builder: cardBody, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: AppSpace.lg, children: [
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [for (final kind in AffiliateRecordKind.values) FButton(variant: _kind == kind ? FButtonVariant.secondary : FButtonVariant.ghost, selected: _kind == kind, mainAxisSize: MainAxisSize.min, onPress: () => setState(() { _kind = kind; _page = 1; }), child: Text(kind == AffiliateRecordKind.referrals ? '邀请记录' : '收益明细'))]),
        if (records.hasError) _failure('邀请记录读取失败', records.error!, () => ref.invalidate(affiliateRecordsProvider(query)))
        else records.when(skipLoadingOnRefresh: false, data: _records, loading: () => const StatePanel(title: '正在读取邀请记录', loading: true), error: (error, _) => _failure('邀请记录读取失败', error, () => ref.invalidate(affiliateRecordsProvider(query)))),
      ])),
    ]))));
  }
}
