import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../state/node_controller.dart';
import '../theme/neu.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/avatar.dart';
import 'call.dart';
import 'camera.dart';
import 'chat.dart';
import 'settings.dart';
import 'settings/account_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final NodeController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _callScreenOpen = false;
  bool _listenerAttached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_listenerAttached) {
      _listenerAttached = true;
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    if (_listenerAttached) {
      widget.controller.removeListener(_onControllerChanged);
      _listenerAttached = false;
    }
    super.dispose();
  }

  void _onControllerChanged() {
    final call = widget.controller.call;
    if (call == null) return;
    if (call.phase != CallPhase.incoming) return;
    if (_callScreenOpen) return;
    _callScreenOpen = true;
    final controller = widget.controller;
    final callId = call.callId;
    final peer = call.peer;
    final video = call.video;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_callScreenOpen) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            controller: controller,
            peer: peer,
            callId: callId,
            isIncoming: true,
            video: video,
          ),
        ),
      ).whenComplete(() => _callScreenOpen = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: [
          ChatsPage(controller: widget.controller),
          AccountPage(controller: widget.controller, embedded: true),
          SettingsPage(controller: widget.controller),
          CameraPage(controller: widget.controller),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 14),
        // Scaffold lays the bottom bar out with loose full-height constraints.
        // A plain Center would expand to the whole screen and float the dock
        // in the middle, so shrink it to the dock's height.
        child: Center(
          heightFactor: 1,
          child: Neu(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            radius: Tokens.radiusRound,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DockButton(
                  icon: Icons.chat_bubble_rounded,
                  label: strings.get('chats'),
                  active: _index == 0,
                  reduceMotion: widget.controller.settings.reduceMotion,
                  onTap: () => setState(() => _index = 0),
                ),
                const SizedBox(width: 8),
                _DockButton(
                  icon: Icons.person_rounded,
                  label: strings.get('account'),
                  active: _index == 1,
                  reduceMotion: widget.controller.settings.reduceMotion,
                  onTap: () => setState(() => _index = 1),
                ),
                const SizedBox(width: 8),
                _DockButton(
                  icon: Icons.settings_rounded,
                  label: strings.get('settings'),
                  active: _index == 2,
                  reduceMotion: widget.controller.settings.reduceMotion,
                  onTap: () => setState(() => _index = 2),
                ),
                const SizedBox(width: 8),
                _DockButton(
                  icon: Icons.photo_camera_rounded,
                  label: strings.get('camera'),
                  active: _index == 3,
                  reduceMotion: widget.controller.settings.reduceMotion,
                  onTap: () => setState(() => _index = 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.reduceMotion,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 50,
          height: 50,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedScale(
                scale: active ? 1 : 0.55,
                duration: duration,
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: active ? 1 : 0,
                  duration: duration,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: withOpacity(accent, 0.32),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedScale(
                scale: active ? 1.08 : 1,
                duration: duration,
                curve: Curves.easeOutCubic,
                child: Icon(
                  icon,
                  size: 21,
                  color: active ? readableOn(accent) : Tokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key, required this.controller});

  final NodeController controller;

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openChat(PersonInfo person) async {
    await widget.controller.setActivePeer(person.deviceId);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          controller: widget.controller,
          deviceId: person.deviceId,
        ),
      ),
    );
    await widget.controller.setActivePeer(null);
  }

  List<PersonInfo> _visiblePeople() {
    final query = _query.trim().toLowerCase();
    final people = widget.controller.people
        .where((person) => !person.hiddenByPeer)
        .where((person) {
          if (query.isEmpty) return true;
          if (person.name.toLowerCase().contains(query)) return true;
          return widget.controller
              .messagesFor(person.deviceId)
              .any((message) => message.body.toLowerCase().contains(query));
        })
        .toList();
    people.sort((a, b) {
      final selfA = widget.controller.isSelf(a.deviceId);
      final selfB = widget.controller.isSelf(b.deviceId);
      if (selfA != selfB) return selfA ? -1 : 1;
      final recent = widget.controller
          .lastActivityFor(b.deviceId)
          .compareTo(widget.controller.lastActivityFor(a.deviceId));
      if (recent != 0) return recent;
      if (a.online != b.online) return a.online ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return people;
  }

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final controller = widget.controller;
    final people = _visiblePeople();
    final accent = Theme.of(context).colorScheme.primary;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AccountPage(controller: controller, embedded: false),
                    ),
                  ),
                  child: KinlyAvatar(
                    name: controller.name,
                    avatarBase64: controller.avatarBase64,
                    size: 44,
                    showDot: false,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.get('chats'),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Tokens.textPrimary,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        controller.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                NeuIconButton(
                  icon: Icons.add_rounded,
                  accent: true,
                  size: 46,
                  iconSize: 24,
                  tooltip: strings.get('chats'),
                  onPressed: () async {
                    await controller.refresh();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          controller.people.isEmpty
                              ? strings.get('noPeople')
                              : '${controller.people.length}',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Neu(
              inset: true,
              radius: Tokens.radiusLarge,
              child: TextField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                style: const TextStyle(color: Tokens.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: strings.get('search'),
                  hintStyle: const TextStyle(
                    color: Tokens.textMuted,
                    fontSize: 13.5,
                  ),
                  border: InputBorder.none,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Tokens.textMuted,
                    size: 20,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Tokens.textMuted,
                          ),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: people.isEmpty
                ? _EmptyPeople(hasQuery: _query.isNotEmpty)
                : RefreshIndicator(
                    color: accent,
                    backgroundColor: Tokens.surface,
                    onRefresh: controller.refresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 110),
                      itemCount: people.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        thickness: 1,
                        indent: 78,
                        endIndent: 8,
                        color: withOpacity(Colors.white, 0.035),
                      ),
                      itemBuilder: (context, index) {
                        final person = people[index];
                        return _PersonTile(
                          controller: controller,
                          person: person,
                          onTap: () => _openChat(person),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPeople extends StatelessWidget {
  const _EmptyPeople({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 90),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Neu(
              width: 92,
              height: 92,
              radius: Tokens.radiusRound,
              inset: true,
              child: Icon(
                Icons.wifi_tethering_rounded,
                color: Tokens.textMuted,
                size: 34,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              hasQuery ? strings.get('noPeople') : strings.get('noPeople'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Tokens.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              strings.get('noPeopleBody'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Tokens.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.controller,
    required this.person,
    required this.onTap,
  });

  final NodeController controller;
  final PersonInfo person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final last = controller.lastMessageFor(person.deviceId);
    final unread = controller.unreadFor(person.deviceId);
    final typing = controller.isTyping(person.deviceId);
    final isSelf = controller.isSelf(person.deviceId);
    final hidden = !person.visible && !isSelf;

    final preview = typing
        ? strings.get('typing')
        : last?.body ??
              (isSelf
                  ? strings.get('onlyOnThisDevice')
                  : person.online
                  ? strings.get('online')
                  : strings.get('hiddenFromYou'));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tokens.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
        child: Row(
          children: [
            KinlyAvatar(
              name: person.name,
              avatarBase64: person.avatar,
              online: person.online,
              size: 52,
              muted: hidden,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            text: person.name,
                            children: [
                              if (isSelf)
                                TextSpan(
                                  text: ' (${strings.get('you')})',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Tokens.textMuted,
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: hidden
                                ? Tokens.textSecondary
                                : Tokens.textPrimary,
                          ),
                        ),
                      ),
                      if (hidden) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.visibility_off_rounded,
                          size: 13,
                          color: Tokens.textMuted,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: typing
                          ? accent
                          : hidden
                          ? Tokens.textMuted
                          : Tokens.textSecondary,
                      fontStyle: typing ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  listTime(last?.createdAt ?? 0, strings.language),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500,
                    color: unread > 0 ? accent : Tokens.textMuted,
                  ),
                ),
                const SizedBox(height: 5),
                if (unread > 0)
                  AccentPill(
                    label: unread > 99 ? '99+' : '$unread',
                    compact: true,
                  )
                else
                  const SizedBox(height: 18),
              ],
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}
