import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/models.dart';

enum AffiliateRecordKind { referrals, earnings }

class AffiliateProgram {
  const AffiliateProgram({required this.enabled, required this.inviterGrant, required this.inviteeGrant, required this.commissionEnabled, required this.commissionRateBps, required this.commissionMode});
  factory AffiliateProgram.fromJson(Json value) {
    if (value['enabled'] is! bool || value['commissionEnabled'] is! bool || !['first', 'all'].contains(value['commissionMode'])) throw const ApiException('邀请活动规则格式异常，请重试');
    return AffiliateProgram(enabled: value['enabled'] as bool, inviterGrant: _integer(value, 'inviterGrant'), inviteeGrant: _integer(value, 'inviteeGrant'), commissionEnabled: value['commissionEnabled'] as bool, commissionRateBps: _integer(value, 'commissionRateBps'), commissionMode: value['commissionMode'] as String);
  }
  final bool enabled, commissionEnabled;
  final int inviterGrant, inviteeGrant, commissionRateBps;
  final String commissionMode;
}

class AffiliateOverview {
  const AffiliateOverview({required this.code, required this.program, required this.stats});
  factory AffiliateOverview.fromJson(Json value) {
    if (value['code'] is! String || (value['code'] as String).isEmpty || value['settings'] is! Map || value['stats'] is! Map) throw const ApiException('邀请信息格式异常，请重试');
    final stats = jsonObject(value['stats']);
    return AffiliateOverview(code: value['code'] as String, program: AffiliateProgram.fromJson(jsonObject(value['settings'])), stats: {for (final key in ['registered', 'verified', 'inviteCredits', 'signupCredits', 'commissionCredits']) key: _integer(stats, key)});
  }
  final String code;
  final AffiliateProgram program;
  final Map<String, int> stats;
}

class AffiliateRecords {
  const AffiliateRecords({required this.items, required this.total});
  final List<Json> items;
  final int total;
}

int _integer(Json value, String key) {
  final number = value[key];
  if (number is! int || number < 0) throw const ApiException('邀请数据格式异常，请重试');
  return number;
}

String affiliateLink(String origin, String code) => Uri.parse(origin).resolve('/register').replace(queryParameters: {'ref': code}).toString();

class AffiliateService {
  const AffiliateService(this.api);
  final ApiClient api;

  Future<Json> _get(String path, {Map<String, dynamic>? query, CancelToken? cancelToken}) async {
    final response = await api.request(path, query: query, cancelToken: cancelToken);
    if (response.data is! Map) throw const ApiException('邀请接口返回格式异常，请重试');
    return jsonObject(response.data);
  }

  Future<AffiliateProgram> program({CancelToken? cancelToken}) async => AffiliateProgram.fromJson(await _get('/affiliate/program', cancelToken: cancelToken));
  Future<AffiliateOverview> overview({CancelToken? cancelToken}) async => AffiliateOverview.fromJson(await _get('/affiliate', cancelToken: cancelToken));

  Future<AffiliateRecords> records(AffiliateRecordKind kind, int page, {CancelToken? cancelToken}) async {
    final value = await _get('/affiliate/${kind.name}', query: {'page': page}, cancelToken: cancelToken);
    if (value['items'] is! List) throw const ApiException('邀请记录格式异常，请重试');
    final items = <Json>[];
    for (final item in value['items'] as List) {
      if (item is! Map) throw const ApiException('邀请记录格式异常，请重试');
      final record = jsonObject(item);
      for (final key in ['id', 'inviteeName', 'createdAt', if (kind == AffiliateRecordKind.earnings) 'kind' else 'status']) {
        if (record[key] is! String || (record[key] as String).isEmpty) throw const ApiException('邀请记录格式异常，请重试');
      }
      if (DateTime.tryParse(record['createdAt'] as String) == null) throw const ApiException('邀请记录时间格式异常，请重试');
      if (kind == AffiliateRecordKind.referrals) {
        if (record['enabled'] is! bool || (record['activatedAt'] != null && (record['activatedAt'] is! String || DateTime.tryParse(record['activatedAt'] as String) == null))) throw const ApiException('邀请状态格式异常，请重试');
      } else {
        _integer(record, 'amount');
        _integer(record, 'rateBps');
      }
      items.add(record);
    }
    return AffiliateRecords(items: items, total: _integer(value, 'total'));
  }
}
