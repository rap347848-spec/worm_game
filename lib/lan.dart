import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'net.dart';

/// غرفة واي فاي: اتصال مباشر عبر الشبكة المحلية (نفس الراوتر أو نقطة اتصال المضيف).
/// أسرع وأثبت من البلوتوث، ومستقلة تماماً عنه.

const int kLanUdpPort = 47611; // للاكتشاف
const int kLanTcpPort = 47612; // للعب

Future<List<String>> localIps() async {
  final out = <String>[];
  try {
    final ifs = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    for (final i in ifs) {
      for (final a in i.addresses) {
        out.add(a.address);
      }
    }
  } catch (_) {}
  return out;
}

Stream<String> _lines(Socket s) => s
    .cast<List<int>>()
    .transform(utf8.decoder)
    .transform(const LineSplitter());

class LanHost extends HostLink {
  ServerSocket? _server;
  RawDatagramSocket? _udp;
  Timer? _timer;
  final Map<String, Socket> _socks = {};
  final Map<String, PeerInfo> peers = {};
  int _n = 0;
  int port = kLanTcpPort;
  List<String> ips = [];
  bool running = false;

  LanHost(String name, int level) : super(name, level);

  @override
  double get snapshotHz => 20.0;

  @override
  List<PeerInfo> get ready =>
      peers.values.where((p) => p.connected && p.hello).toList();

  @override
  Future<bool> start() async {
    try {
      try {
        _server = await ServerSocket.bind(InternetAddress.anyIPv4, kLanTcpPort,
            shared: true);
      } catch (_) {
        _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      }
      port = _server!.port;
      _server!.listen(_onClient, onError: (_) {});
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udp!.broadcastEnabled = true;
      ips = await localIps();
      _announce();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _announce());
      running = true;
    } catch (_) {
      running = false;
    }
    return running;
  }

  void _announce() {
    final u = _udp;
    if (u == null) return;
    final data = utf8.encode(jsonEncode({'g': 'worm', 'n': name, 'p': port}));
    final targets = <String>{'255.255.255.255'};
    for (final ip in ips) {
      final p = ip.split('.');
      if (p.length == 4) targets.add('${p[0]}.${p[1]}.${p[2]}.255');
    }
    for (final t in targets) {
      try {
        u.send(data, InternetAddress(t), kLanUdpPort);
      } catch (_) {}
    }
  }

  void _onClient(Socket s) {
    final id = 'lan${_n++}';
    try {
      s.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    _socks[id] = s;
    final p = PeerInfo(id, 'لاعب');
    p.connected = true;
    peers[id] = p;
    onChanged?.call();
    _lines(s).listen((line) {
      try {
        _handle(id, jsonDecode(line) as Map<String, dynamic>);
      } catch (_) {}
    }, onDone: () => _drop(id), onError: (_) => _drop(id), cancelOnError: true);
  }

  void _handle(String id, Map<String, dynamic> m) {
    if (m['t'] == 'hello') {
      final p = peers[id];
      if (p != null) {
        p.name = (m['name'] ?? p.name) as String;
        p.level = ((m['level'] ?? 1) as num).toInt();
        p.hello = true;
      }
      broadcastLobby();
      onChanged?.call();
    } else {
      onMessage?.call(id, m);
    }
  }

  void _drop(String id) {
    if (peers.remove(id) != null) {
      try {
        _socks.remove(id)?.destroy();
      } catch (_) {}
      onLeft?.call(id);
      broadcastLobby();
      onChanged?.call();
    }
  }

  @override
  void broadcastLobby() {
    broadcast({
      't': 'lobby',
      'p': [
        [name, level],
        for (final p in ready) [p.name, p.level],
      ],
    });
  }

  @override
  void send(String id, Map<String, dynamic> m) {
    try {
      _socks[id]?.write('${jsonEncode(m)}\n');
    } catch (_) {}
  }

  @override
  void broadcast(Map<String, dynamic> m) {
    final line = '${jsonEncode(m)}\n';
    for (final s in _socks.values) {
      try {
        s.write(line);
      } catch (_) {}
    }
  }

  @override
  void stop() {
    _timer?.cancel();
    for (final s in _socks.values) {
      try {
        s.destroy();
      } catch (_) {}
    }
    _socks.clear();
    peers.clear();
    try {
      _server?.close();
      _udp?.close();
    } catch (_) {}
    running = false;
  }
}

class LanClient extends ClientLink {
  RawDatagramSocket? _udp;
  Timer? _prune;
  Socket? _sock;
  final Map<String, int> _seen = {};
  @override
  bool connected = false;
  bool discovering = false;

  LanClient(String name, int level) : super(name, level);

  @override
  Future<bool> startDiscovery() async {
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kLanUdpPort,
          reuseAddress: true);
      _udp!.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final d = _udp?.receive();
        if (d == null) return;
        try {
          final m = jsonDecode(utf8.decode(d.data)) as Map<String, dynamic>;
          if (m['g'] != 'worm') return;
          final id = '${d.address.address}:${m['p']}';
          final isNew = !hosts.containsKey(id);
          hosts[id] = (m['n'] ?? '') as String;
          _seen[id] = DateTime.now().millisecondsSinceEpoch;
          if (isNew) onHostsChanged?.call();
        } catch (_) {}
      });
      _prune = Timer.periodic(const Duration(seconds: 2), (_) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final stale = <String>[];
        _seen.forEach((k, v) {
          if (now - v > 4500) stale.add(k);
        });
        if (stale.isEmpty) return;
        for (final k in stale) {
          _seen.remove(k);
          hosts.remove(k);
        }
        onHostsChanged?.call();
      });
      discovering = true;
    } catch (_) {
      discovering = false;
    }
    return discovering;
  }

  /// id بصيغة "عنوان:منفذ" أو عنوان فقط (للإدخال اليدوي).
  @override
  Future<void> connect(String id) async {
    hostId = id;
    final parts = id.trim().split(':');
    final ip = parts[0];
    final port =
        parts.length > 1 ? (int.tryParse(parts[1]) ?? kLanTcpPort) : kLanTcpPort;
    try {
      final s = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 6));
      try {
        s.setOption(SocketOption.tcpNoDelay, true);
      } catch (_) {}
      _sock = s;
      connected = true;
      _lines(s).listen((line) {
        try {
          onMessage?.call(jsonDecode(line) as Map<String, dynamic>);
        } catch (_) {}
      }, onDone: _lost, onError: (_) => _lost(), cancelOnError: true);
      send({'t': 'hello', 'name': name, 'level': level});
      onConnected?.call();
    } catch (_) {
      connected = false;
      hostId = null;
      onDisconnected?.call();
    }
  }

  void _lost() {
    if (!connected) return;
    connected = false;
    onDisconnected?.call();
  }

  @override
  void send(Map<String, dynamic> m) {
    try {
      _sock?.write('${jsonEncode(m)}\n');
    } catch (_) {}
  }

  @override
  void stop() {
    _prune?.cancel();
    try {
      _udp?.close();
      _sock?.destroy();
    } catch (_) {}
    connected = false;
    discovering = false;
  }
}
