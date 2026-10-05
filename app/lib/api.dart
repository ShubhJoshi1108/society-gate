import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Single place that talks to the society server.
class Api {
  Api._();
  static final Api I = Api._();

  late SharedPreferences prefs;
  PocketBase? _pb;

  PocketBase get pb => _pb!;
  bool get hasServer => _pb != null;
  String get serverUrl => prefs.getString('server_url') ?? '';

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    if (serverUrl.isNotEmpty) _connect(serverUrl);
  }

  void _connect(String url) {
    final store = AsyncAuthStore(
      save: (String data) async => prefs.setString('pb_auth', data),
      initial: prefs.getString('pb_auth'),
      clear: () async => prefs.remove('pb_auth'),
    );
    _pb = PocketBase(url, authStore: store);
  }

  static String normalizeUrl(String input) {
    var u = input.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Future<void> login(String server, String email, String password) async {
    final url = normalizeUrl(server);
    if (url != serverUrl || _pb == null) {
      await prefs.setString('server_url', url);
      await prefs.remove('pb_auth');
      _connect(url);
    }
    await pb.collection('users').authWithPassword(email.trim(), password);
  }

  Future<void> logout() async {
    try {
      pb.realtime.unsubscribe();
    } catch (_) {}
    pb.authStore.clear();
  }

  bool get isLoggedIn => hasServer && pb.authStore.isValid && pb.authStore.record != null;
  RecordModel get me => pb.authStore.record!;
  String get role => me.getStringValue('role');
  String get myFlat => me.getStringValue('flat');

  Future<void> refreshAuth() async {
    if (!isLoggedIn) return;
    try {
      await pb.collection('users').authRefresh();
    } catch (_) {
      pb.authStore.clear();
    }
  }

  // ---------------- flats & users ----------------
  /// All houses, in numeric order (1, 2, 3 … 400).
  Future<List<RecordModel>> flats() async {
    final list = await pb.collection('flats').getFullList();
    int n(RecordModel r) => int.tryParse(r.getStringValue('label')) ?? 1 << 30;
    list.sort((a, b) {
      final c = n(a).compareTo(n(b));
      return c != 0 ? c : a.getStringValue('label').compareTo(b.getStringValue('label'));
    });
    return list;
  }

  Future<List<RecordModel>> residentsOf(String flatId) => pb.collection('users').getFullList(
        filter: pb.filter("flat = {:f} && role = 'resident'", {'f': flatId}),
        sort: 'name',
      );

  // ---------------- visits ----------------
  Future<List<RecordModel>> visits({String? filter, int perPage = 100}) async {
    final res = await pb.collection('visits').getList(
          page: 1,
          perPage: perPage,
          filter: filter ?? '',
          sort: '-created',
          expand: 'flat',
        );
    return res.items;
  }

  Future<RecordModel> createVisit(Map<String, dynamic> body, {List<int>? photo}) {
    final files = <http.MultipartFile>[];
    if (photo != null) {
      files.add(http.MultipartFile.fromBytes('photo', photo, filename: 'visitor.jpg'));
    }
    return pb.collection('visits').create(body: body, files: files, expand: 'flat');
  }

  Future<RecordModel> getVisit(String id) => pb.collection('visits').getOne(id, expand: 'flat');

  Future<void> decide(String visitId, String decision) => pb.send(
        '/api/gate/visits/$visitId/decide',
        method: 'POST',
        body: {'decision': decision},
      );

  Future<void> checkout(String visitId) =>
      pb.send('/api/gate/visits/$visitId/checkout', method: 'POST');

  Future<UnsubscribeFunc> watchVisits(void Function(RecordSubscriptionEvent e) cb) =>
      pb.collection('visits').subscribe('*', cb, expand: 'flat');

  String photoUrl(RecordModel visit) {
    final f = visit.getStringValue('photo');
    if (f.isEmpty) return '';
    return pb.files.getURL(visit, f, thumb: '300x300').toString();
  }

  // ---------------- passes ----------------
  Future<List<RecordModel>> passes() => pb.collection('passes').getFullList(sort: '-created');

  Future<RecordModel> createPass(Map<String, dynamic> body) =>
      pb.collection('passes').create(body: {...body, 'flat': myFlat});

  Future<void> deletePass(String id) => pb.collection('passes').delete(id);

  // ---------------- push ----------------
  Future<Map<String, dynamic>> pushInfo() async {
    final res = await pb.send('/api/gate/me/push');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> pushTest() => pb.send('/api/gate/me/push-test', method: 'POST');

  static String errorText(Object e) {
    if (e is ClientException) {
      final msg = e.response['message'];
      final data = e.response['data'];
      if (data is Map && data.isNotEmpty) {
        final first = data.values.first;
        if (first is Map && first['message'] != null) return '${data.keys.first}: ${first['message']}';
      }
      if (msg is String && msg.isNotEmpty) return msg;
      if (e.statusCode == 0) return 'Cannot reach server. Check internet / server address.';
    }
    return e.toString();
  }
}
