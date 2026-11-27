import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../l10n/strings.dart';
import '../state/node_controller.dart';
import '../theme/neu.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/avatar.dart';

/// Full-screen call UI. Phase 3 of PLAN.md: voice on Android first, video on
/// Android only. WebRTC runs between the two peer connections; the signaling
/// (offer / answer / ICE / hangup) goes through the encrypted channel via the
/// node's call signal frames.
class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.controller,
    required this.peer,
    required this.callId,
    required this.isIncoming,
    required this.video,
  });

  final NodeController controller;
  final String peer;
  final String callId;
  final bool isIncoming;
  final bool video;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  Timer? _timer;
  DateTime? _startedAt;
  bool _connecting = true;
  bool _micOn = true;
  bool _cameraOn = true;
  bool _speakerOn = true;
  bool _frontCamera = true;
  bool _remoteSet = false;
  String? _appliedAnswerSdp;
  int _appliedCandidates = 0;

  CallState? get _call => widget.controller.call;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _boot();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _timer?.cancel();
    _timer = null;
    unawaited(_pc?.dispose());
    unawaited(_localRenderer.dispose());
    unawaited(_remoteRenderer.dispose());
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      final pc = await createPeerConnection(<String, dynamic>{
        // No STUN/TURN: ICE uses local-network candidates only (PLAN.md 7.7).
        'iceServers': <Map<String, dynamic>>[],
      });
      _pc = pc;
      pc.onIceCandidate = (RTCIceCandidate candidate) {
        widget.controller.sendCallSignal(
          peer: widget.peer,
          callId: widget.callId,
          payload: jsonEncode(<String, dynamic>{
            'type': 'candidate',
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }),
        );
      };
      pc.onConnectionState = (RTCPeerConnectionState state) {
        if (!mounted) return;
        setState(() => _connecting =
            state != RTCPeerConnectionState.RTCPeerConnectionStateConnected);
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _startedAt ??= DateTime.now();
          _timer?.cancel();
          _timer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
        }
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _timer?.cancel();
          _timer = null;
        }
      };
      pc.onTrack = (RTCTrackEvent event) {
        final stream = event.streams.isNotEmpty ? event.streams.first : null;
        if (stream != null) _remoteRenderer.srcObject = stream;
      };

      final stream = await mediaDevices.getUserMedia(<String, dynamic>{
        'audio': true,
        'video': widget.video ? <String, dynamic>{'facingMode': 'user'} : false,
      });
      if (!mounted) return;
      _localStream = stream;
      // Unified Plan WebRTC has no addStream(); attach each track instead.
      for (final track in stream.getTracks()) {
        await pc.addTrack(track, stream);
      }
      _localRenderer.srcObject = stream;
      await Helper.setSpeakerphoneOn(_speakerOn);
      if (widget.video) setState(() {});

      if (widget.isIncoming) {
        // The offer from the caller is waiting in the controller until the
        // user accepts; nothing is sent before that.
      } else {
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        await widget.controller.sendCallSignal(
          peer: widget.peer,
          callId: widget.callId,
          payload: jsonEncode(<String, dynamic>{
            'type': 'offer',
            'sdp': offer.sdp,
            'video': widget.video,
          }),
        );
        if (mounted) setState(() => _connecting = false);
      }
    } catch (error) {
      debugPrint('kinly: call boot failed: $error');
      if (mounted) widget.controller.setCallPhase(CallPhase.ended);
    }
  }

  Future<void> _accept() async {
    final pc = _pc;
    if (pc == null || _remoteSet) return;
    final sdp = _call?.offerSdp ?? _call?.lastSignal?['sdp'];
    if (sdp is! String) return;
    final description = RTCSessionDescription(sdp, 'offer');
    await pc.setRemoteDescription(description);
    _remoteSet = true;
    await _applyPendingCandidates();
    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await widget.controller.sendCallSignal(
      peer: widget.peer,
      callId: widget.callId,
      payload: jsonEncode(<String, dynamic>{'type': 'answer', 'sdp': answer.sdp}),
    );
    widget.controller.setCallPhase(CallPhase.ongoing);
    await _applyPendingCandidates();
  }

  void _onControllerChanged() {
    unawaited(_syncSignals());
  }

  Future<void> _syncSignals() async {
    if (!widget.isIncoming) {
      // Outgoing calls must apply the answer; otherwise no media can flow.
      final pc = _pc;
      final sig = _call?.lastSignal;
      if (pc != null && sig != null && sig['type'] == 'answer') {
        final sdp = sig['sdp'];
        if (sdp is String && sdp.isNotEmpty && _appliedAnswerSdp != sdp) {
          _appliedAnswerSdp = sdp;
          await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
          _remoteSet = true;
          widget.controller.setCallPhase(CallPhase.ongoing);
        }
      }
    }
    await _applyPendingCandidates();
  }

  Future<void> _applyPendingCandidates() async {
    final pc = _pc;
    if (pc == null || !_remoteSet) return;
    final candidates = _call?.candidates ?? const <Map<String, dynamic>>[];
    while (_appliedCandidates < candidates.length) {
      final c = candidates[_appliedCandidates];
      _appliedCandidates++;
      final candidate = c['candidate'];
      if (candidate is String && candidate.isNotEmpty) {
        final index = c['sdpMLineIndex'];
        await pc.addCandidate(
          RTCIceCandidate(
            candidate,
            c['sdpMid'] is String ? c['sdpMid'] as String : null,
            index is num ? index.toInt() : null,
          ),
        );
      }
    }
  }

  Future<void> _hangUp() async {
    await widget.controller.endCall();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleMic() async {
    final enabled = !_micOn;
    _micOn = enabled;
    final tracks = _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    for (final track in tracks) {
      track.enabled = enabled;
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleSpeaker() async {
    final enabled = !_speakerOn;
    _speakerOn = enabled;
    await Helper.setSpeakerphoneOn(enabled);
    if (mounted) setState(() {});
  }

  Future<void> _flipCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    final switched = await Helper.switchCamera(tracks.first);
    if (!switched) return;
    _frontCamera = !_frontCamera;
    if (mounted) setState(() {});
  }

  Future<void> _toggleCamera() async {
    final enabled = !_cameraOn;
    _cameraOn = enabled;
    final tracks = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    for (final track in tracks) {
      track.enabled = enabled;
    }
    if (mounted) setState(() {});
  }

  String _statusText() {
    final phase = _call?.phase;
    final strings = StringsScope.of(context);
    if (phase == CallPhase.incoming) return strings.get('incomingCall');
    if (phase == CallPhase.outgoing) {
      return _connecting ? strings.get('connecting') : strings.get('calling');
    }
    if (phase == CallPhase.ongoing) {
      final started = _startedAt;
      final elapsed =
          started == null ? Duration.zero : DateTime.now().difference(started);
      return '${strings.get('inCall')} · ${formatCallDuration(elapsed)}';
    }
    return strings.get('callFailed');
  }

  @override
  Widget build(BuildContext context) {
    final phase = _call?.phase;
    final isOngoing = phase == CallPhase.ongoing;
    final useVideoLayout = widget.video && isOngoing;

    return Scaffold(
      backgroundColor: Tokens.background,
      body: SafeArea(
        child: useVideoLayout
            ? _buildVideoCall(context)
            : _buildVoiceCall(context, phase ?? CallPhase.ended, isOngoing),
      ),
    );
  }

  Widget _buildVoiceCall(
    BuildContext context,
    CallPhase phase,
    bool isOngoing,
  ) {
    final strings = StringsScope.of(context);
    final controller = widget.controller;
    final accent = Theme.of(context).colorScheme.primary;
    final name = controller.person(widget.peer)?.name ?? widget.peer.substring(0, 8);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 48),
            KinlyAvatar(
              name: name,
              avatarBase64: controller.avatarBase64,
              size: 128,
              muted: phase == CallPhase.outgoing && _connecting,
            ),
            const SizedBox(height: 20),
            Text(
              name,
              style: const TextStyle(
                color: Tokens.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusText(),
              style: TextStyle(
                color: phase == CallPhase.ongoing ? accent : Tokens.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (phase == CallPhase.incoming) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CallActionButton(
                    background: Tokens.danger,
                    icon: Icons.phone_missed,
                    label: strings.get('decline'),
                    onPressed: _hangUp,
                  ),
                  const SizedBox(width: 22),
                  _CallActionButton(
                    background: Tokens.success,
                    icon: Icons.phone,
                    label: strings.get('accept'),
                    onPressed: _accept,
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isOngoing) ...[
                    NeuIconButton(
                      icon: _micOn ? Icons.mic : Icons.mic_off,
                      size: 56,
                      iconSize: 24,
                      accent: !_micOn,
                      tooltip: strings.get('mute'),
                      onPressed: _toggleMic,
                    ),
                    const SizedBox(width: 12),
                    NeuIconButton(
                      icon: _speakerOn
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      size: 56,
                      iconSize: 24,
                      accent: !_speakerOn,
                      tooltip: strings.get('speaker'),
                      onPressed: _toggleSpeaker,
                    ),
                    const SizedBox(width: 12),
                  ],
                  const SizedBox(width: 18),
                  _CallActionButton(
                    background: Tokens.danger,
                    icon: Icons.call_end,
                    label: strings.get('endCall'),
                    onPressed: _hangUp,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCall(BuildContext context) {
    final strings = StringsScope.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: RTCVideoView(
            _remoteRenderer,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
        ),
        Positioned(
          right: 16,
          bottom: 140,
          child: SizedBox(
            width: 112,
            height: 160,
            child: RTCVideoView(
              _localRenderer,
              mirror: _frontCamera,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 34,
                    backgroundColor: Tokens.surface,
                    child: Icon(Icons.person_rounded, color: Tokens.textPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.controller.person(widget.peer)?.name ??
                          widget.peer.substring(0, 8),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Tokens.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  NeuIconButton(
                    icon: _micOn ? Icons.mic : Icons.mic_off,
                    size: 40,
                    iconSize: 18,
                    accent: !_micOn,
                    tooltip: strings.get('mute'),
                    onPressed: _toggleMic,
                  ),
                  NeuIconButton(
                    icon: _speakerOn
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    size: 40,
                    iconSize: 18,
                    accent: !_speakerOn,
                    tooltip: strings.get('speaker'),
                    onPressed: _toggleSpeaker,
                  ),
                  NeuIconButton(
                    icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
                    size: 40,
                    iconSize: 18,
                    tooltip: strings.get('videoCall'),
                    onPressed: _toggleCamera,
                  ),
                  NeuIconButton(
                    icon: Icons.cameraswitch_rounded,
                    size: 40,
                    iconSize: 18,
                    tooltip: strings.get('flipCamera'),
                    onPressed: _flipCamera,
                  ),
                  NeuIconButton(
                    icon: Icons.call_end,
                    size: 48,
                    iconSize: 20,
                    onPressed: _hangUp,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.background,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final Color background;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: background,
            boxShadow: [
              BoxShadow(
                color: withOpacity(background, 0.45),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 30,
            color: readableOn(background),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(
            color: Tokens.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
