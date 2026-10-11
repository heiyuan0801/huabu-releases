import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api/api_client.dart';
import '../../core/models.dart';

enum AuthMode { login, register, reset }

class AuthNotice {
  const AuthNotice({required this.title, required this.message, this.warning});
  final String title, message;
  final String? warning;
}

class RegistrationResult {
  const RegistrationResult({required this.email, required this.emailSent, required this.message});
  final String email, message;
  final bool emailSent;
}

class AuthRepository {
  const AuthRepository(this.api);
  final ApiClient api;

  Future<Json> request(String path, {Map<String, dynamic>? body, required CancelToken token}) async {
    final response = await api.request(path, method: body == null ? 'GET' : 'POST', body: body, cancelToken: token);
    final data = response.data is String ? jsonDecode(response.data as String) : response.data;
    if (data is! Map) throw const ApiException('账号服务返回格式异常，请稍后重试');
    return jsonObject(data);
  }

  Future<RegistrationResult> register(Map<String, dynamic> body, CancelToken token) async {
    final result = await request('/auth/register', body: body, token: token);
    if (jsonString(result['email']).isEmpty || result['emailSent'] is! bool || result['verificationRequired'] != true) {
      throw const ApiException('注册状态无法确认，请先检查邮箱或返回登录完成验证');
    }
    return RegistrationResult(email: result['email'] as String, emailSent: result['emailSent'] as bool, message: jsonString(result['message']));
  }

  Future<String> sendCode(Map<String, dynamic> body, String purpose, CancelToken token) async {
    final result = await request('/auth/send-code', body: {...body, 'purpose': purpose}, token: token);
    final message = jsonString(result['message']);
    if (message.isEmpty) throw const ApiException('验证码发送状态无法确认，请检查邮箱');
    return message;
  }

  Future<String> resetPassword(Map<String, dynamic> body, CancelToken token) async {
    final result = await request('/auth/reset-password', body: body, token: token);
    final message = jsonString(result['message']);
    if (message.isEmpty) throw const ApiException('密码重置状态无法确认，请返回登录核对');
    return message;
  }
}
