import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

/// اللعب عبر البلوتوث والواي فاي المباشر (Nearby Connections على أندرويد).
/// المضيف هو الذي يشغّل اللعبة، والباقي يرسلون حركة أصابعهم ويستقبلون الصورة.

const String kService = 'com.wormgame.worms';

Uint8List _enc(Map<String, dynamic> m) =>
    Uint8List.fromList(utf8.encode(jsonEncode(m)));

Map<String, dynamic>? _dec(Payload p) {
  if (p.type != PayloadType.BYTES || p.bytes == null) return null;
  try {
    return jsonDecode(utf8.decode(p.bytes!)) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Future<bool> ensureNearbyPermissions() async {
  try {
    final res = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.nearbyWifiDevices,
    ].request();
    return res[Permission.location]?.isGranted ?? false;
  } catch (_) {
    return false;
  }
}

class PeerInfo {
  final String endpoint;
  String name;
  int level = 1;
  bool connected = false;
  bool hello = false;
  PeerInfo(this.endpoint, this.name);
}

class NetHost {
  final String name;
  final int level;
  final Map<String, PeerInfo> peers = {};
  bool running = false;

  VoidCallback? onChanged;
  void Function(String peer, Map<String, dynamic> msg)? onMessage;
  void Function(String peer)? onLeft;

  NetHost(this.name, this.level);

  List<PeerInfo> get ready =>
      peers.values.where((p) => p.connected && p.hello).toList();

  Future<bool> start() async {
    try {
      running = await Nearby().startAdvertising(
        name,
        Strategy.P2P_STAR,
        onConnectionInitiated: (id, info) {
          peers[id] = PeerInfo(id, info.endpointName);
          Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (eid, payload) {
              final m = _dec(payload);
              if (m != null) _handle(eid, m);
            },
            onPayloadTransferUpdate: (eid, upd) {},
          );
          onChanged?.call();
        },
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            peers[id]?.connected = true;
          } else {
            peers.remove(id);
          }
          onChanged?.call();
        },
        onDisconnected: (id) {
          peers.remove(id);
          onLeft?.call(id);
          broadcastLobby();
          onChanged?.call();
        },
        serviceId: kService,
      );
    } catch (_) {
      running = false;
    }
    return running;
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

  void broadcastLobby() {
    broadcast({
      't': 'lobby',
      'p': [
        [name, level],
        for (final p in ready) [p.name, p.level],
      ],
    });
  }

  void send(String id, Map<String, dynamic> m) {
    try {
      Nearby().sendBytesPayload(id, _enc(m));
    } catch (_) {}
  }

  void broadcast(Map<String, dynamic> m) {
    final bytes = _enc(m);
    for (final p in peers.values) {
      if (!p.connected) continue;
      try {
        Nearby().sendBytesPayload(p.endpoint, bytes);
      } catch (_) {}
    }
  }

  void stop() {
    try {
      Nearby().stopAdvertising();
      Nearby().stopAllEndpoints();
    } catch (_) {}
    running = false;
  }
}

class NetClient {
  final String name;
  final int level;
  final Map<String, String> hosts = {}; // endpoint -> اسم المضيف
  String? hostId;
  bool connected = false;
  bool discovering = false;

  VoidCallback? onHostsChanged;
  VoidCallback? onConnected;
  VoidCallback? onDisconnected;
  void Function(Map<String, dynamic> msg)? onMessage;

  NetClient(this.name, this.level);

  Future<bool> startDiscovery() async {
    try {
      discovering = await Nearby().startDiscovery(
        name,
        Strategy.P2P_STAR,
        onEndpointFound: (id, userName, serviceId) {
          hosts[id] = userName;
          onHostsChanged?.call();
        },
        onEndpointLost: (id) {
          if (id != null) hosts.remove(id);
          onHostsChanged?.call();
        },
        serviceId: kService,
      );
    } catch (_) {
      discovering = false;
    }
    return discovering;
  }

  Future<void> connect(String id) async {
    hostId = id;
    try {
      await Nearby().requestConnection(
        name,
        id,
        onConnectionInitiated: (eid, info) {
          Nearby().acceptConnection(
            eid,
            onPayLoadRecieved: (e, payload) {
              final m = _dec(payload);
              if (m != null) onMessage?.call(m);
            },
            onPayloadTransferUpdate: (e, upd) {},
          );
        },
        onConnectionResult: (eid, status) {
          if (status == Status.CONNECTED) {
            connected = true;
            send({'t': 'hello', 'name': name, 'level': level});
            onConnected?.call();
          } else {
            connected = false;
            hostId = null;
            onDisconnected?.call();
          }
        },
        onDisconnected: (eid) {
          connected = false;
          onDisconnected?.call();
        },
      );
    } catch (_) {
      hostId = null;
      onDisconnected?.call();
    }
  }

  void send(Map<String, dynamic> m) {
    final id = hostId;
    if (id == null) return;
    try {
      Nearby().sendBytesPayload(id, _enc(m));
    } catch (_) {}
  }

  void stop() {
    try {
      Nearby().stopDiscovery();
      Nearby().stopAllEndpoints();
    } catch (_) {}
    connected = false;
    discovering = false;
  }
}
