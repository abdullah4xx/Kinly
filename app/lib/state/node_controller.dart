import 'dart:async';

import 'package:flutter/foundation.dart';

import '../src/rust/api.dart';
import 'settings.dart';

export '../src/rust/api.dart' show PersonInfo;

/// One message as the UI needs it.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.peer,
    required this.outgoing,
    required this.body,
    required this.state,
    required this.createdAt,
  });

  final String id;
  final String peer;
  final bool outgoing;
  final String body;
  final String state;
  final int createdAt;

  bool get unread => !outgoing && state != 'read';

  ChatMessage copyWith({String? state}) => ChatMessage(
    id: id,
    peer: peer,
    outgoing: outgoing,
    body: body,
    state: state ?? this.state,
    createdAt: createdAt,
  );

  factory ChatMessage.fromInfo(MessageInfo info) => ChatMessage(
    id: info.id,
    peer: info.peer,
    outgoing: info.direction == 'out',
    body: info.body,
    state: info.state,
    createdAt: info.createdAt.toInt(),
  );
}

/// Progress of an incoming or outgoing file transfer.
class TransferInfo {
  TransferInfo({
    required this.id,
    required this.peer,
    required this.outgoing,
    required this.name,
    this.total = 0,
    this.received = 0,
    this.path = '',
    this.failed = false,
    this.done = false,
    this.cancelled = false,
  });

  final String id;
  final String peer;
  final bool outgoing;
  final String name;
  int total;
  int received;
  String path;
  bool failed;
  bool done;
  bool cancelled;

  /// Bytes per second, sampled while progress events arrive.
  double speed = 0;
  int _lastReceived = 0;
  DateTime _lastSample = DateTime.now();

  double get progress => total <= 0 ? 0 : (received / total).clamp(0, 1);

  void sampleProgress(int newReceived, int newTotal) {
    final now = DateTime.now();
    final elapsed = now.difference(_lastSample).inMilliseconds;
    if (elapsed >= 400) {
      final delta = newReceived - _lastReceived;
      if (delta >= 0) {
        speed = delta * 1000 / elapsed;
      }
      _lastReceived = newReceived;
      _lastSample = now;
    }
    received = newReceived;
    total = newTotal;
  }
}

/// Owns the Rust node and mirrors its state for the widgets.
class NodeController extends ChangeNotifier {
  NodeController(this.settings);

  final AppSettings settings;

  KinlyNode? node;
  String name = '';
  String deviceId = '';
  String dataDir = '';
  String? avatarBase64;
  String? startError;
  bool starting = false;
  bool _disposed = false;

  List<PersonInfo> _people = const [];
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, TransferInfo> _transfers = {};
  final Map<String, bool> _typing = {};
  final Map<String, Timer> _typingTimers = {};
  final Set<String> _loadedHistory = {};

  String? activePeer;
  String? lastError;
  bool nameConflict = false;
  String? conflictName;

  Timer? _poll;
  Timer? _refresh;
  bool _busy = false;

  List<PersonInfo> get people => _people;

  bool get ready => node != null;

  String? get dataName => name;

  List<ChatMessage> messagesFor(String peer) =>
      List.unmodifiable(_messages[peer] ?? const []);

  List<TransferInfo> transfersFor(String peer) => _transfers.values
      .where((transfer) => transfer.peer == peer && !transfer.cancelled)
      .toList(growable: false);

  bool isTyping(String peer) => _typing[peer] ?? false;

  int unreadFor(String peer) =>
      (_messages[peer] ?? const []).where((message) => message.unread).length;

  ChatMessage? lastMessageFor(String peer) {
    final list = _messages[peer];
    if (list == null || list.isEmpty) return null;
    return list.last;
  }

  int lastActivityFor(String peer) {
    final last = lastMessageFor(peer);
    return last?.createdAt ?? 0;
  }

  PersonInfo? person(String deviceId) {
    for (final person in _people) {
      if (person.deviceId == deviceId) return person;
    }
    return null;
  }

  /// True when [otherDeviceId] is this device, i.e. a chat with yourself.
  bool isSelf(String otherDeviceId) =>
      deviceId.isNotEmpty && otherDeviceId == deviceId;

  /// How long the native node may take to open before the app gives up and
  /// shows the retry screen instead of spinning forever.
  static const _startTimeout = Duration(seconds: 25);
  static const _refreshTimeout = Duration(seconds: 8);

  Future<KinlyNode> _openNode({
    required String name,
    required String dataDir,
    required bool enableMdns,
  }) {
    return startNode(
      options: StartOptions(
        name: name,
        dataDir: dataDir,
        listenPort: 0,
        enableMdns: enableMdns,
      ),
    ).timeout(_startTimeout);
  }

  Future<void> start({required String dataDir, required String name}) async {
    if (_disposed || node != null || starting) return;
    this.dataDir = dataDir;
    starting = true;
    startError = null;
    lastError = null;
    notifyListeners();
    try {
      KinlyNode started;
      try {
        started = await _openNode(
          name: name,
          dataDir: dataDir,
          enableMdns: true,
        );
      } on TimeoutException {
        // mDNS is optional. If opening multicast sockets wedged the native
        // side, start again without it so chat still works.
        debugPrint('kinly: start timed out, retrying without mDNS');
        started = await _openNode(
          name: name,
          dataDir: dataDir,
          enableMdns: false,
        );
      }
      node = started;
      this.name = started.name();
      deviceId = started.deviceId();
      avatarBase64 = started.avatar();
      // Show the chat list now; the first refresh must not hold the splash.
      if (!_disposed) notifyListeners();
      await settings.rememberName(this.name);
      _poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
        _drainEvents();
      });
      _refresh = Timer.periodic(const Duration(seconds: 2), (_) {
        refresh();
      });
      await refresh();
    } catch (error) {
      startError = error.toString();
      debugPrint('kinly: start failed: $error');
    } finally {
      starting = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _drainEvents() {
    final current = node;
    if (current == null) return;
    final events = current.pollEvents();
    if (events.isEmpty) return;
    var structural = false;
    for (final event in events) {
      switch (event.kind) {
        case 'peer_up':
        case 'peer_down':
        case 'visibility':
        case 'profile_changed':
          structural = true;
        case 'name_conflict':
          nameConflict = true;
          conflictName = event.name;
          structural = true;
        case 'message':
          if (event.deviceId.isNotEmpty) {
            _appendMessage(
              event.deviceId,
              ChatMessage(
                id: event.messageId,
                peer: event.deviceId,
                outgoing: false,
                body: event.body,
                state: event.state.isEmpty ? 'delivered' : event.state,
                createdAt: event.offset.toInt(),
              ),
            );
            if (activePeer == event.deviceId) {
              markRead(event.deviceId);
            }
          }
        case 'message_state':
          _updateMessageState(event.messageId, event.state);
        case 'typing':
          _setTyping(event.deviceId, event.typing);
        case 'file_offer':
          _transfers[event.transferId] = TransferInfo(
            id: event.transferId,
            peer: event.deviceId,
            outgoing: false,
            name: event.name,
            total: event.size.toInt(),
            received: event.offset.toInt(),
          );
        case 'file_progress':
          final transfer = _transfers[event.transferId];
          if (transfer != null) {
            transfer.sampleProgress(
              event.received.toInt(),
              event.total.toInt(),
            );
          }
        case 'file_complete':
          final transfer = _transfers[event.transferId];
          if (transfer != null) {
            transfer
              ..done = true
              ..path = event.path
              ..received = transfer.total;
          }
        case 'file_failed':
          final transfer = _transfers[event.transferId];
          if (transfer != null) {
            transfer.failed = true;
            lastError = event.error;
          }
        case 'file_sent':
          final transfer = _transfers[event.transferId];
          if (transfer != null) {
            transfer.done = true;
          }
        case 'error':
          lastError = event.error;
        case 'call_signal':
          break;
      }
    }
    if (structural) refresh();
    notifyListeners();
  }

  void _appendMessage(String peer, ChatMessage message) {
    final list = _messages.putIfAbsent(peer, () => []);
    if (list.any((existing) => existing.id == message.id)) return;
    list.add(message);
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  void _updateMessageState(String messageId, String state) {
    for (final entry in _messages.entries) {
      final list = entry.value;
      for (var index = 0; index < list.length; index++) {
        if (list[index].id == messageId) {
          list[index] = list[index].copyWith(state: state);
          return;
        }
      }
    }
    // The message may not be loaded yet; a refresh will pick it up.
    refresh();
  }

  void _setTyping(String peer, bool typing) {
    _typing[peer] = typing;
    _typingTimers.remove(peer)?.cancel();
    if (typing) {
      _typingTimers[peer] = Timer(const Duration(seconds: 4), () {
        if (_disposed) return;
        _typing[peer] = false;
        notifyListeners();
      });
    }
  }

  Future<void> refresh() async {
    final current = node;
    if (current == null || _busy || _disposed) return;
    _busy = true;
    try {
      final people = await current.people().timeout(_refreshTimeout);
      _people = people;
      for (final person in people) {
        if (!_loadedHistory.contains(person.deviceId)) {
          _loadedHistory.add(person.deviceId);
          await _loadHistory(person.deviceId);
        }
      }
      if (!_disposed) notifyListeners();
    } catch (error) {
      debugPrint('kinly: refresh failed: $error');
    } finally {
      _busy = false;
    }
  }

  Future<void> _loadHistory(String peer) async {
    final current = node;
    if (current == null) return;
    try {
      final history = await current.history(deviceId: peer, limit: 80);
      _messages[peer] = history.map(ChatMessage.fromInfo).toList();
      if (activePeer == peer && _messages[peer]!.any((m) => m.unread)) {
        await markRead(peer);
      }
    } catch (error) {
      debugPrint('kinly: history failed: $error');
    }
  }

  Future<void> _reload(String peer) async {
    _loadedHistory.add(peer);
    await _loadHistory(peer);
    if (!_disposed) notifyListeners();
  }

  Future<void> sendMessage(String peer, String body) async {
    final current = node;
    if (current == null || body.trim().isEmpty) return;
    try {
      await current.sendMessage(deviceId: peer, body: body.trim());
      await _reload(peer);
      await refresh();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<void> sendFile(String peer, String path, {String? displayName}) async {
    final current = node;
    if (current == null) return;
    try {
      final id = await current.sendFile(deviceId: peer, path: path);
      _transfers[id] = TransferInfo(
        id: id,
        peer: peer,
        outgoing: true,
        name: displayName ?? path.split(RegExp(r'[/\\]')).last,
      );
      notifyListeners();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<void> cancelTransfer(TransferInfo transfer) async {
    final current = node;
    if (current == null) return;
    try {
      await current.cancelFile(transferId: transfer.id);
      transfer.cancelled = true;
      notifyListeners();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<void> setVisibility(String peer, bool visible) async {
    final current = node;
    if (current == null) return;
    try {
      await current.setVisibility(deviceId: peer, visible: visible);
      await refresh();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<void> setTyping(String peer, bool typing) async {
    final current = node;
    if (current == null) return;
    try {
      await current.setTyping(deviceId: peer, typing: typing);
    } catch (_) {
      // Typing indicators are best effort.
    }
  }

  /// This device's identity fingerprint, or an empty string before start.
  String get fingerprint {
    try {
      return node?.fingerprint() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// The 60-digit code shared with [peer], or an empty string on error.
  String safetyCodeFor(String peer) {
    try {
      return node?.safetyCode(deviceId: peer) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> retryMessage(String messageId) async {
    final current = node;
    if (current == null) return;
    try {
      await current.retryMessage(messageId: messageId);
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<void> markRead(String peer) async {
    final current = node;
    if (current == null) return;
    try {
      await current.markRead(deviceId: peer);
      final list = _messages[peer];
      if (list != null) {
        for (var index = 0; index < list.length; index++) {
          if (list[index].unread) {
            list[index] = list[index].copyWith(state: 'read');
          }
        }
        notifyListeners();
      }
    } catch (error) {
      debugPrint('kinly: mark read failed: $error');
    }
  }

  Future<void> setActivePeer(String? peer) async {
    activePeer = peer;
    if (peer != null) {
      _loadedHistory.add(peer);
      await _loadHistory(peer);
      await markRead(peer);
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> updateProfile({
    String? name,
    String? avatarBase64,
    bool removeAvatar = false,
  }) async {
    final current = node;
    if (current == null) return;
    try {
      await current.setProfile(
        name: name ?? '',
        avatarBase64: avatarBase64 ?? '',
        removeAvatar: removeAvatar,
      );
      this.name = current.name();
      this.avatarBase64 = current.avatar();
      await settings.rememberName(this.name);
      notifyListeners();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Stops the node and clears its state so the welcome screen can retry with
  /// a different name.
  Future<void> reset() async {
    _poll?.cancel();
    _refresh?.cancel();
    _poll = null;
    _refresh = null;
    await node?.shutdown();
    node = null;
    _people = const [];
    _messages.clear();
    _transfers.clear();
    _typing.clear();
    _loadedHistory.clear();
    activePeer = null;
    startError = null;
    nameConflict = false;
    conflictName = null;
    starting = false;
    name = '';
    deviceId = '';
    avatarBase64 = null;
    notifyListeners();
  }

  /// Shuts the node down and erases the identity, database and downloads.
  Future<void> wipe() async {
    final directory = dataDir;
    await reset();
    if (directory.isNotEmpty) {
      await wipeData(dataDir: directory);
    }
    await settings.forgetName();
  }

  Future<void> shutdown() async {
    _poll?.cancel();
    _refresh?.cancel();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    await node?.shutdown();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _refresh?.cancel();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    unawaited(node?.shutdown());
    super.dispose();
  }
}
