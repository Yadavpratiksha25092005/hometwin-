import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'notifications.dart';

/// Do modes (lib/config.dart ka kApiUrl decide karta hai):
///  * DEMO (kApiUrl empty): no backend, all data is kept in the phone's local storage.
///  * SERVER (kApiUrl set): Go backend (/api/...) se baat karta hai.
class Api {
  static String? userName;
  static String? _token;

  static bool get remote => kApiUrl.isNotEmpty;
  static String get _base => kApiUrl.replaceFirst(RegExp(r'/+$'), '');

  static Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  static Future<bool> loadSession() async {
    final p = await _p;
    if (remote) {
      _token = p.getString('token');
      userName = p.getString('name');
      return _token != null;
    }
    userName = p.getString('name');
    return p.getBool('loggedIn') ?? false;
  }

  static Future<void> logout() async {
    final p = await _p;
    _token = null;
    await Notifications.cancelAll();
    await p.remove('token');
    await p.remove('loggedIn');
    await p.remove('name');
  }

  static Map<String, dynamic> _users(SharedPreferences p) =>
      Map<String, dynamic>.from(jsonDecode(p.getString('users') ?? '{}'));

  static Future<void> _start(SharedPreferences p, String name) async {
    userName = name;
    await p.setBool('loggedIn', true);
    await p.setString('name', name);
  }

  static Future<void> register(String name, String email, String pass,
      {String phone = ''}) async {
    if (remote) {
      return _remoteAuth('/api/auth/register', {'name': name, 'email': email.trim(), 'password': pass, 'phone': phone});
    }
    final p = await _p;
    final key = email.trim().toLowerCase();
    if (key.isEmpty || pass.length < 6) {
      throw Exception('Email and password (min 6 characters) are required');
    }
    final users = _users(p);
    if (users.containsKey(key)) throw Exception('This email is already registered');
    users[key] = {'name': name, 'pass': pass, 'phone': phone};
    await p.setString('users', jsonEncode(users));
    await _start(p, name);
  }

  static Future<void> login(String email, String pass) async {
    if (remote) return _remoteAuth('/api/auth/login', {'email': email.trim(), 'password': pass});
    final p = await _p;
    final u = _users(p)[email.trim().toLowerCase()];
    if (u == null || u['pass'] != pass) throw Exception('Incorrect email or password');
    await _start(p, u['name']);
  }

  /// Demo mode: email se seedha naya password set hota hai.
  /// On a real backend this should be done with an email/SMS OTP.
  static Future<void> resetPassword(String email, String newPass) async {
    if (remote) throw Exception('Password reset is not available in server mode yet');
    final p = await _p;
    final key = email.trim().toLowerCase();
    final users = _users(p);
    if (!users.containsKey(key)) throw Exception('No account found with this email');
    if (newPass.length < 6) throw Exception('Password must be at least 6 characters');
    users[key] = {...Map<String, dynamic>.from(users[key]), 'pass': newPass};
    await p.setString('users', jsonEncode(users));
  }

  // ---------- server (Go backend) ----------
  static String get _down =>
      'Could not connect to the server ($_base). Is the backend running? Are your phone and computer on the same Wi-Fi?';

  static Future<http.Response> _send(String method, String path, {Object? body, bool auth = true}) async {
    final req = http.Request(method, Uri.parse('$_base$path'));
    req.headers['Content-Type'] = 'application/json';
    if (auth && _token != null) req.headers['Authorization'] = 'Bearer $_token';
    if (body != null) req.body = jsonEncode(body);
    try {
      final streamed = await req.send().timeout(const Duration(seconds: 20));
      return await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw Exception(_down);
    } on SocketException {
      throw Exception(_down);
    } on http.ClientException {
      throw Exception(_down);
    }
  }

  /// JSON request. The server's error message is thrown as an Exception.
  static Future<dynamic> _req(String method, String path, {Object? body, bool auth = true}) async {
    final r = await _send(method, path, body: body, auth: auth);
    dynamic data;
    if (r.body.isNotEmpty) {
      try {
        data = jsonDecode(r.body);
      } catch (_) {}
    }
    if (r.statusCode == 401) {
      if (auth) {
        await logout();
        throw Exception('Session expired. Please log in again');
      }
      throw Exception('Incorrect email or password');
    }
    if (r.statusCode == 409) throw Exception('This email is already registered');
    if (r.statusCode >= 400) {
      throw Exception(data is Map && data['error'] != null ? '${data['error']}' : 'Server error (${r.statusCode})');
    }
    return data;
  }

  static Future<void> _remoteAuth(String path, Map<String, dynamic> body) async {
    final d = await _req('POST', path, body: body, auth: false);
    final p = await _p;
    _token = d['token'] as String;
    userName = '${d['user']['name']}';
    await p.setString('token', _token!);
    await p.setString('name', userName!);
    await p.setBool('loggedIn', true);
  }

  static Future<String> _remoteUpload(String path) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_base/api/upload'));
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    req.files.add(await http.MultipartFile.fromPath('file', path));
    try {
      final r = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 3)));
      if (r.statusCode == 401) {
        await logout();
        throw Exception('Session expired. Please log in again');
      }
      if (r.statusCode >= 400) throw Exception('Upload failed (${r.statusCode}). File must be smaller than 50 MB');
      return '${jsonDecode(r.body)['url']}';
    } on TimeoutException {
      throw Exception(_down);
    } on SocketException {
      throw Exception(_down);
    } on http.ClientException {
      throw Exception(_down);
    }
  }

  /// '/files/abc.jpg' (server) ya poora http URL -> network par dikhane layak URL.
  static bool isServerPath(String? s) => s != null && (s.startsWith('/files/') || s.startsWith('http'));
  static String fileUrl(String s) => s.startsWith('http') ? s : '$_base$s';

  /// Document / photo ko phone par File bana ke deta hai. Server file ho to download (cache) karta hai.
  static Future<File?> localFile(String? p) async {
    if (p == null || p.isEmpty) return null;
    if (!isServerPath(p)) {
      final f = File(p);
      return f.existsSync() ? f : null;
    }
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/dl_${p.split('/').last}');
    if (f.existsSync()) return f;
    final r = await http.get(Uri.parse(fileUrl(p))).timeout(const Duration(minutes: 2));
    if (r.statusCode != 200) return null;
    await f.writeAsBytes(r.bodyBytes);
    return f;
  }

  /// Room Designer: sends a furniture photo to the server's 3D service (POST /api/furniture/generate).
  /// Returns the job id, or null when there is no 3D service (demo mode, or the server does not have it yet).
  static Future<String?> furnitureStart(String photoPath) async {
    if (!remote) return null;
    final req = http.MultipartRequest('POST', Uri.parse('$_base/api/furniture/generate'));
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    req.files.add(await http.MultipartFile.fromPath('file', photoPath));
    try {
      final r = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 2)));
      if (r.statusCode == 401) {
        await logout();
        throw Exception('Session expired. Please log in again');
      }
      if (r.statusCode == 404 || r.statusCode == 405 || r.statusCode == 501) return null; // no 3D service on this server
      if (r.statusCode >= 400) throw Exception('3D service error (${r.statusCode})');
      final d = jsonDecode(r.body);
      final id = d is Map ? (d['job_id'] ?? d['id']) : null;
      return id == null ? null : '$id';
    } on TimeoutException {
      throw Exception(_down);
    } on SocketException {
      throw Exception(_down);
    } on http.ClientException {
      throw Exception(_down);
    }
  }

  /// Progress of a 3D job: {status: processing|ready|failed, progress, model_url, error}.
  static Future<Map<String, dynamic>> furnitureStatus(String jobId) async {
    final d = await _req('GET', '/api/furniture/generate/$jobId');
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{'status': 'failed', 'error': 'Bad answer from the server'};
  }

  /// Furniture hosted on the server (uploads/furniture/<Category>/<name>.png). Empty in demo mode.
  static Future<List<dynamic>> furnitureCatalog() async {
    if (!remote) return [];
    final d = await _req('GET', '/api/furniture', auth: false);
    return d is List ? List<dynamic>.from(d) : [];
  }

  /// Downloads a server image once and keeps it on the phone (kept between app restarts).
  static Future<File?> cachedFile(String p) async {
    if (!isServerPath(p)) {
      final f = File(p);
      return f.existsSync() ? f : null;
    }
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/furniture_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final f = File('${dir.path}/${p.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}');
    if (f.existsSync() && f.lengthSync() > 0) return f;
    try {
      final r = await http.get(Uri.parse(fileUrl(p))).timeout(const Duration(minutes: 1));
      if (r.statusCode != 200) return null;
      await f.writeAsBytes(r.bodyBytes);
      return f;
    } catch (_) {
      return null;
    }
  }

  // ---------- CRUD (server or local) ----------
  static Future<List<dynamic>> list(String res) async {
    if (remote) return List<dynamic>.from(await _req('GET', '/api/$res') as List);
    final p = await _p;
    final items = List<dynamic>.from(jsonDecode(p.getString('db_$res') ?? '[]'));
    return items.reversed.toList(); // newest first
  }

  static Future<int> create(String res, Map<String, dynamic> data) async {
    if (remote) {
      final d = await _req('POST', '/api/$res', body: data);
      _resync(res);
      return (d['id'] as num).toInt();
    }
    final p = await _p;
    final items = List<dynamic>.from(jsonDecode(p.getString('db_$res') ?? '[]'));
    final id = (p.getInt('seq_$res') ?? 0) + 1;
    await p.setInt('seq_$res', id);
    items.add({...data, 'id': id, 'created_at': DateTime.now().toIso8601String()});
    await p.setString('db_$res', jsonEncode(items));
    _resync(res);
    return id;
  }

  /// Keeps scheduled reminders in step with task / warranty changes.
  static void _resync(String res) {
    if (res == 'tasks' || res == 'warranties' || res == 'assets') Notifications.sync();
  }

  static Future<void> remove(String res, int id) async {
    if (remote) {
      await _req('DELETE', '/api/$res/$id');
      _resync(res);
      return;
    }
    final p = await _p;
    final items = List<dynamic>.from(jsonDecode(p.getString('db_$res') ?? '[]'));
    items.removeWhere((e) => e['id'] == id);
    await p.setString('db_$res', jsonEncode(items));
    _resync(res);
  }

  /// Demo mode: files are not uploaded, only the local file path is saved.
  static Future<String> upload(String path) async {
    if (remote) return _remoteUpload(path);
    return path;
  }

  static Future<List<dynamic>> reminders() async {
    if (remote) return List<dynamic>.from(await _req('GET', '/api/reminders') as List);
    final warranties = await list('warranties');
    final assets = await list('assets');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <Map<String, dynamic>>[];
    for (final w in warranties) {
      final exp = DateTime.tryParse('${w['expiry_date']}');
      if (exp == null) continue;
      final days = exp.difference(today).inDays;
      if (days < -7 || days > 30) continue;
      final asset = assets.firstWhere((a) => a['id'] == w['asset_id'], orElse: () => null);
      out.add({
        'asset': asset?['name'],
        'provider': w['provider'],
        'expiry_date': w['expiry_date'],
        'days_left': days,
      });
    }
    out.sort((a, b) => (a['days_left'] as int).compareTo(b['days_left'] as int));
    return out;
  }

  static Future<String> report() async {
    if (remote) {
      final r = await _send('GET', '/api/export/report');
      if (r.statusCode >= 400) throw Exception('Could not create report (${r.statusCode})');
      return r.body;
    }
    return _localReport();
  }

  static Future<String> _localReport() async => jsonEncode({
        'assets': await list('assets'),
        'warranties': await list('warranties'),
        'repairs': await list('repairs'),
        'documents': await list('documents'),
        'tasks': await list('tasks'),
        'generated_at': DateTime.now().toIso8601String(),
      });

  // ---------- sample data ----------
  static Future<void> clearData() async {
    if (remote) {
      // delete all own records on the server (documents/tasks/... first, assets last)
      for (final res in ['documents', 'repairs', 'tasks', 'warranties', 'scans', 'assets']) {
        for (final it in await list(res)) {
          await remove(res, (it['id'] as num).toInt());
        }
      }
      return;
    }
    final p = await _p;
    for (final k in p.getKeys().toList()) {
      if (k.startsWith('db_') || k.startsWith('seq_')) await p.remove(k);
    }
    await Notifications.cancelAll();
  }

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<void> seedDemo() async {
    final now = DateTime.now();
    const img = 'asset:assets/images/demo/';

    final fridge = await create('assets', {'name': 'Refrigerator', 'brand': 'Samsung', 'model': 'RS75R5411M9', 'room': 'Kitchen', 'category': 'Appliance', 'purchase_date': '2022-12-15', 'price': '84999', 'photo_url': '${img}fridge.jpg'});
    final sofa = await create('assets', {'name': 'Sofa', 'brand': 'IKEA', 'model': 'KIVIK 3-seater', 'room': 'Living Room', 'category': 'Furniture', 'purchase_date': '2023-06-20', 'price': '45000', 'photo_url': '${img}sofa.jpg'});
    final washer = await create('assets', {'name': 'Washing Machine', 'brand': 'LG', 'model': 'FHV1208Z5W', 'room': 'Utility', 'category': 'Appliance', 'purchase_date': '2021-03-10', 'price': '38000', 'photo_url': '${img}washer.jpg'});
    final ac = await create('assets', {'name': 'AC (Living Room)', 'brand': 'Daikin', 'model': 'FTKM50TV16U', 'room': 'Living Room', 'category': 'Appliance', 'purchase_date': '2022-11-25', 'price': '52000', 'photo_url': '${img}ac.jpg'});
    final heater = await create('assets', {'name': 'Water Heater', 'brand': 'Racold', 'model': '25L', 'room': 'Bathroom', 'category': 'Appliance', 'purchase_date': '2024-01-10', 'price': '9500'});

    await create('warranties', {'asset_id': fridge, 'provider': 'Samsung', 'start_date': '2022-12-15', 'expiry_date': '2027-12-15'});
    await create('warranties', {'asset_id': sofa, 'provider': 'IKEA', 'start_date': '2023-06-20', 'expiry_date': '2028-06-20'});
    await create('warranties', {'asset_id': washer, 'provider': 'LG', 'start_date': '2021-03-10', 'expiry_date': '2024-03-10'});
    await create('warranties', {'asset_id': ac, 'provider': 'Daikin', 'start_date': '2022-11-25', 'expiry_date': '2027-11-25'});

    await create('documents', {'asset_id': fridge, 'title': 'Fridge invoice', 'category': 'Invoice'});
    await create('documents', {'asset_id': sofa, 'title': 'Sofa receipt', 'category': 'Receipt'});
    await create('documents', {'asset_id': washer, 'title': 'Washer invoice', 'category': 'Invoice'});
    await create('documents', {'asset_id': washer, 'title': 'Washer warranty card', 'category': 'Warranty'});
    await create('documents', {'asset_id': ac, 'title': 'AC invoice', 'category': 'Invoice'});

    Future<void> task(int asset, String title, int daysLeft, int total) => create('tasks', {
          'asset_id': asset,
          'title': title,
          'due_date': _d(now.add(Duration(days: daysLeft))),
          'start_date': _d(now.add(Duration(days: daysLeft - total))),
        });
    await task(ac, 'Filter Cleaning & Service', 15, 60);
    await task(washer, 'General Service', 32, 64);
    await task(heater, 'Annual Service', 78, 78);

    await create('repairs', {'asset_id': ac, 'title': 'AC Service', 'repair_date': '2025-05-12', 'service_provider': 'Daikin'});
  }
}