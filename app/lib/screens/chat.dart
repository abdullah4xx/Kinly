import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../state/node_controller.dart';
import '../theme/neu.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/avatar.dart';
import 'security.dart';

const _imageTypes = XTypeGroup(
  label: 'Images',
  extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
);

/// One-to-one conversation with all message states, file transfers, the
/// visibility toggle and the safety code.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.controller,
    required this.deviceId,
  });

  final NodeController controller;
  final String deviceId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  Timer? _typingStop;
  int _renderedCount = -1;

  String get _peer => widget.deviceId;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _text.removeListener(_onTextChanged);
    if (_typingStop != null) {
      widget.controller.setTyping(_peer, false);
    }
    _typingStop?.cancel();
    _text.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {});
    if (_text.text.trim().isEmpty) {
      _typingStop?.cancel();
      _typingStop = null;
      widget.controller.setTyping(_peer, false);
      return;
    }
    if (_typingStop == null) {
      widget.controller.setTyping(_peer, true);
    }
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(milliseconds: 2500), () {
      _typingStop = null;
      widget.controller.setTyping(_peer, false);
    });
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (animated && !widget.controller.settings.reduceMotion) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    _text.clear();
    _typingStop?.cancel();
    _typingStop = null;
    widget.controller.setTyping(_peer, false);
    await widget.controller.sendMessage(_peer, body);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _pickFile({bool imagesOnly = false}) async {
    final strings = StringsScope.of(context);
    try {
      final file = await openFile(
        acceptedTypeGroups: imagesOnly ? const [_imageTypes] : const [],
      );
      if (file == null) return;
      await widget.controller.sendFile(
        _peer,
        file.path,
        displayName: file.name,
      );
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${strings.get('fileFailed')}: $error')),
      );
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final controller = widget.controller;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final person = controller.person(_peer);
            final messages = controller.messagesFor(_peer);
            final transfers = controller.transfersFor(_peer);
            final count = messages.length + transfers.length;
            if (count != _renderedCount) {
              _renderedCount = count;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _scrollToBottom(animated: count > 1),
              );
            }

            final items = <Object>[];
            DateTime? day;
            for (final message in messages) {
              final date = dateOf(message.createdAt);
              final sameDay =
                  day != null &&
                  date.year == day.year &&
                  date.month == day.month &&
                  date.day == day.day;
              if (!sameDay) {
                day = date;
                items.add(dayLabel(date, strings.language));
              }
              items.add(message);
            }
            items.addAll(transfers);

            return Column(
              children: [
                _ChatHeader(
                  controller: controller,
                  person: person,
                  deviceId: _peer,
                  onVerify: person == null
                      ? null
                      : () => showPeerSecurity(context, controller, person),
                  onCall: () => _snack(strings.get('callsSoon')),
                ),
                if (person != null && (!person.visible || person.hiddenByPeer))
                  _HiddenBanner(
                    controller: controller,
                    person: person,
                  ),
                Expanded(
                  child: items.isEmpty
                      ? _EmptyChat(strings: strings)
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            if (item is String) {
                              return _DaySeparator(label: item);
                            }
                            if (item is ChatMessage) {
                              return _Bubble(
                                message: item,
                                strings: strings,
                                reduceMotion: controller.settings.reduceMotion,
                                onRetry: () =>
                                    controller.retryMessage(item.id),
                              );
                            }
                            final transfer = item as TransferInfo;
                            return _TransferBubble(
                              transfer: transfer,
                              strings: strings,
                              onCancel: () =>
                                  controller.cancelTransfer(transfer),
                              onCopyPath: transfer.path.isEmpty
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                        ClipboardData(text: transfer.path),
                                      );
                                      if (!context.mounted) return;
                                      _snack(strings.get('copied'));
                                    },
                            );
                          },
                        ),
                ),
                _Composer(
                  controller: controller,
                  text: _text,
                  focus: _focus,
                  onSend: _send,
                  onAttach: () => _pickFile(),
                  onPhoto: () => _pickFile(imagesOnly: true),
                  onMic: () => _snack(strings.get('voiceNoteSoon')),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.controller,
    required this.person,
    required this.deviceId,
    required this.onVerify,
    required this.onCall,
  });

  final NodeController controller;
  final PersonInfo? person;
  final String deviceId;
  final VoidCallback? onVerify;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final typing = controller.isTyping(deviceId);
    final name = person?.name ?? deviceId.substring(0, 8);
    final hiddenByPeer = person?.hiddenByPeer ?? false;

    final String status;
    if (typing) {
      status = strings.get('typing');
    } else if (hiddenByPeer) {
      status = strings.get('theyHidYou');
    } else if (person?.online ?? false) {
      status = strings.get('online');
    } else if ((person?.lastSeen ?? BigInt.zero) > BigInt.zero) {
      status =
          '${strings.get('lastSeen')} '
          '${listTime(person!.lastSeen.toInt(), strings.language)}';
    } else {
      status = strings.get('offline');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          NeuIconButton(
            icon: Icons.arrow_back_rounded,
            accent: true,
            size: 42,
            iconSize: 19,
            tooltip: strings.get('close'),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onVerify,
            child: KinlyAvatar(
              name: name,
              avatarBase64: person?.avatar,
              online: person?.online ?? false,
              size: 44,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: GestureDetector(
              onTap: onVerify,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Tokens.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: typing ? accent : Tokens.textSecondary,
                      fontSize: 11.5,
                      fontStyle: typing
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (person != null)
            NeuIconButton(
              icon: person!.visible
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              size: 42,
              iconSize: 18,
              tooltip: person!.visible
                  ? strings.get('visibility')
                  : strings.get('hidden'),
              onPressed: () =>
                  controller.setVisibility(deviceId, !person!.visible),
            ),
          const SizedBox(width: 8),
          NeuIconButton(
            icon: Icons.call_rounded,
            accent: true,
            size: 44,
            iconSize: 20,
            tooltip: strings.get('call'),
            onPressed: onCall,
          ),
        ],
      ),
    );
  }
}

class _HiddenBanner extends StatelessWidget {
  const _HiddenBanner({required this.controller, required this.person});

  final NodeController controller;
  final PersonInfo person;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final theyHid = person.hiddenByPeer;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: withOpacity(Tokens.surfaceHigh, 0.7),
        borderRadius: BorderRadius.circular(Tokens.radiusMedium),
        border: Border.all(color: withOpacity(Colors.white, 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.visibility_off_rounded,
            size: 17,
            color: Tokens.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  theyHid ? strings.get('theyHidYou') : strings.get('youHidThem'),
                  style: const TextStyle(
                    color: Tokens.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  strings.get('hiddenChatNotice'),
                  style: const TextStyle(
                    color: Tokens.textSecondary,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
                if (!theyHid) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () =>
                        controller.setVisibility(person.deviceId, true),
                    child: Text(
                      strings.get('showMeAgain'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: withOpacity(Tokens.surfaceHigh, 0.65),
            borderRadius: BorderRadius.circular(Tokens.radiusRound),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Tokens.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.strings,
    required this.reduceMotion,
    required this.onRetry,
  });

  final ChatMessage message;
  final Strings strings;
  final bool reduceMotion;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final outgoing = message.outgoing;
    final textColor = outgoing ? readableOn(accent) : Tokens.textPrimary;
    final secondary = outgoing
        ? withOpacity(readableOn(accent), 0.72)
        : Tokens.textMuted;
    final direction = _textDirection(message.body);

    final bubble = Align(
      alignment: outgoing
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: GestureDetector(
          onLongPress: () async {
            await Clipboard.setData(ClipboardData(text: message.body));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(strings.get('messageCopied')),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 7),
            decoration: BoxDecoration(
              color: outgoing ? accent : Tokens.surfaceHigh,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(Tokens.radiusLarge),
                topRight: const Radius.circular(Tokens.radiusLarge),
                bottomLeft: Radius.circular(outgoing ? Tokens.radiusLarge : 7),
                bottomRight: Radius.circular(outgoing ? 7 : Tokens.radiusLarge),
              ),
              boxShadow: [
                BoxShadow(
                  color: withOpacity(
                    Tokens.shadowDark,
                    outgoing ? 0.35 : 0.45,
                  ),
                  offset: const Offset(2, 3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Directionality(
                  textDirection: direction,
                  child: Text(
                    message.body,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14.5,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      bubbleTime(message.createdAt, strings.language),
                      style: TextStyle(
                        color: secondary,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (outgoing) ...[
                      const SizedBox(width: 5),
                      _StateMark(
                        state: message.state,
                        color: secondary,
                        strings: strings,
                        onRetry: onRetry,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (reduceMotion) return bubble;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 8),
          child: child,
        ),
      ),
      child: bubble,
    );
  }

  static TextDirection _textDirection(String body) {
    final arabic = RegExp(r'[\u0600-\u06FF]');
    return arabic.hasMatch(body) ? TextDirection.rtl : TextDirection.ltr;
  }
}

class _StateMark extends StatelessWidget {
  const _StateMark({
    required this.state,
    required this.color,
    required this.strings,
    required this.onRetry,
  });

  final String state;
  final Color color;
  final Strings strings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state == 'failed') {
      return GestureDetector(
        onTap: onRetry,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 13, color: Tokens.danger),
            const SizedBox(width: 3),
            Text(
              strings.get('retry'),
              style: const TextStyle(
                color: Tokens.danger,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    final (icon, label) = switch (state) {
      'queued' => (Icons.schedule_rounded, 'queued'),
      'sent' => (Icons.check_rounded, 'sent'),
      'delivered' => (Icons.done_all_rounded, 'delivered'),
      'read' => (Icons.done_all_rounded, 'read'),
      _ => (Icons.check_rounded, 'sent'),
    };

    return Tooltip(
      message: strings.get(label),
      child: Icon(icon, size: 13, color: color),
    );
  }
}

class _TransferBubble extends StatelessWidget {
  const _TransferBubble({
    required this.transfer,
    required this.strings,
    required this.onCancel,
    required this.onCopyPath,
  });

  final TransferInfo transfer;
  final Strings strings;
  final VoidCallback onCancel;
  final VoidCallback? onCopyPath;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final outgoing = transfer.outgoing;
    final textColor = outgoing ? readableOn(accent) : Tokens.textPrimary;
    final secondary = outgoing
        ? withOpacity(readableOn(accent), 0.72)
        : Tokens.textSecondary;

    final label = transfer.failed
        ? strings.get('fileFailed')
        : transfer.done
        ? strings.get('fileSaved')
        : outgoing
        ? strings.get('fileSending')
        : strings.get('fileReceiving');

    return Align(
      alignment: outgoing
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: GestureDetector(
          onTap: transfer.done ? onCopyPath : null,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
            decoration: BoxDecoration(
              color: outgoing ? accent : Tokens.surfaceHigh,
              borderRadius: BorderRadius.circular(Tokens.radiusLarge),
              boxShadow: [
                BoxShadow(
                  color: withOpacity(Tokens.shadowDark, 0.45),
                  offset: const Offset(2, 3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      transfer.done
                          ? Icons.insert_drive_file_rounded
                          : Icons.upload_file_rounded,
                      size: 22,
                      color: textColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            transfer.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            transfer.failed
                                ? label
                                : '${formatBytes(transfer.total)} · $label',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: secondary, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    if (!transfer.done && !transfer.failed)
                      GestureDetector(
                        onTap: onCancel,
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: secondary,
                          ),
                        ),
                      ),
                  ],
                ),
                if (!transfer.done && !transfer.failed) ...[
                  const SizedBox(height: 9),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Tokens.radiusRound),
                    child: LinearProgressIndicator(
                      value: transfer.progress == 0
                          ? null
                          : transfer.progress,
                      minHeight: 5,
                      backgroundColor: withOpacity(
                        outgoing ? Colors.black : Colors.white,
                        0.12,
                      ),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        outgoing ? textColor : accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(transfer.progress * 100).round()}%',
                        style: TextStyle(color: secondary, fontSize: 10),
                      ),
                      if (transfer.speed > 0)
                        Text(
                          '${formatBytes(transfer.speed.round())}/s',
                          style: TextStyle(color: secondary, fontSize: 10),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.text,
    required this.focus,
    required this.onSend,
    required this.onAttach,
    required this.onPhoto,
    required this.onMic,
  });

  final NodeController controller;
  final TextEditingController text;
  final FocusNode focus;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onPhoto;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final hasText = text.text.trim().isNotEmpty;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Neu(
              inset: true,
              radius: Tokens.radiusLarge,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.emoji_emotions_outlined,
                      size: 20,
                      color: Tokens.textMuted,
                    ),
                    tooltip: strings.get('messageHint'),
                    onPressed: () {
                      final selection = text.selection;
                      final value = text.text;
                      final at = selection.isValid
                          ? selection.start
                          : value.length;
                      text.value = TextEditingValue(
                        text: '${value.substring(0, at)}🙂${value.substring(at)}',
                        selection: TextSelection.collapsed(offset: at + 2),
                      );
                      focus.requestFocus();
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: text,
                      focusNode: focus,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(
                        color: Tokens.textPrimary,
                        fontSize: 14.5,
                      ),
                      decoration: InputDecoration(
                        hintText: strings.get('messageHint'),
                        hintStyle: const TextStyle(
                          color: Tokens.textMuted,
                          fontSize: 13.5,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.attach_file_rounded,
                      size: 19,
                      color: Tokens.textMuted,
                    ),
                    tooltip: strings.get('attachFile'),
                    onPressed: onAttach,
                  ),
                  if (Platform.isAndroid)
                    IconButton(
                      icon: const Icon(
                        Icons.photo_camera_outlined,
                        size: 19,
                        color: Tokens.textMuted,
                      ),
                      tooltip: strings.get('attachPhoto'),
                      onPressed: onPhoto,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 9),
          NeuIconButton(
            icon: hasText ? Icons.send_rounded : Icons.mic_rounded,
            accent: true,
            size: 54,
            iconSize: 23,
            tooltip: hasText
                ? strings.get('sent')
                : strings.get('voiceNoteSoon'),
            onPressed: hasText ? onSend : onMic,
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Neu(
              width: 82,
              height: 82,
              radius: Tokens.radiusRound,
              inset: true,
              child: Icon(
                Icons.lock_outline_rounded,
                color: Tokens.textMuted,
                size: 30,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              strings.get('noMessages'),
              style: const TextStyle(
                color: Tokens.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              strings.get('noMessagesBody'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Tokens.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
