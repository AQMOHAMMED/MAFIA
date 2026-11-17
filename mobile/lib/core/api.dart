import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class ApiError implements Exception {
  final String message;
  final int status;
  ApiError(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

// الاتصال بنفس API الموقع
class Api {
  String? token;
  void Function()? onUnauthorized;

  Future<dynamic> call(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$kServer/api$path');
    final req = http.Request(method, uri);
    req.headers['Content-Type'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    http.Response res;
    try {
      // السيرفر المجاني بينام، أول طلب ممكن ياخذ وقت
      res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 60)));
    } on TimeoutException {
      throw ApiError('السيرفر ما رد، جرّب كمان شوي');
    } catch (_) {
      throw ApiError('ما في اتصال بالإنترنت');
    }
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {}
    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    if (res.statusCode >= 400) {
      throw ApiError(data is Map && data['error'] is String ? data['error'] : 'صار خطأ، جرّب كمان مرة', res.statusCode);
    }
    return data;
  }

  Future<dynamic> get(String p) => call('GET', p);
  Future<dynamic> post(String p, [Object? b]) => call('POST', p, b ?? {});
  Future<dynamic> put(String p, Object b) => call('PUT', p, b);
  Future<dynamic> delete(String p, Object b) => call('DELETE', p, b);
}
