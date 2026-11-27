import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/strings.dart';
import '../state/node_controller.dart';
import '../theme/neu.dart';
import '../theme/tokens.dart';
import '../widgets/avatar.dart';

/// The fourth dock tab: take a photo and send it, scan a Kinly QR code, or read
/// text from a photo and copy it.
class CameraPage extends StatefulWidget {
  const CameraPage({super.key, required this.controller});

  final NodeController controller;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  XFile? _photo;
  bool _busy = false;

  NodeController get _controller => widget.controller;

  Future<bool> _ensureCamera() async {
    // The camera plugins request the runtime camera permission themselves;
    // we never block on a separate permission package.
    return true;
  }

  Future<void> _takePhoto(BuildContext context) async {
    if (_busy) return;
    final strings = StringsScope.of(context);
    setState(() => _busy = true);
    try {
      if (!await _ensureCamera()) {
        if (!context.mounted) return;
        _snack(context, strings.get('permissionDenied'));
        return;
      }
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );
      if (picked == null || !mounted) return;
      setState(() => _photo = picked);
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, '${strings.get('cameraFailed')} $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendPhoto(BuildContext context) async {
    final photo = _photo;
    if (photo == null) return;
    final strings = StringsScope.of(context);
    final peer = await _pickRecipient(context);
    if (peer == null || !mounted) return;
    try {
      await _controller.sendFile(
        peer,
        photo.path,
        displayName: 'photo-${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      if (!mounted) return;
      setState(() => _photo = null);
      if (!context.mounted) return;
      _snack(context, strings.get('photoSent'));
    } catch (error) {
      if (!context.mounted) return;
      _snack(context, '${strings.get('fileFailed')} $error');
    }
  }

  Future<String?> _pickRecipient(BuildContext context) {
    final strings = StringsScope.of(context);
    final people =
        _controller.people
            .where((person) => !_controller.isSelf(person.deviceId))
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Tokens.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Tokens.textMuted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  strings.get('chooseRecipient'),
                  style: const TextStyle(
                    color: Tokens.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                if (people.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Text(
                      strings.get('noPeopleBody'),
                      style: const TextStyle(
                        color: Tokens.textSecondary,
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: people.length,
                      itemBuilder: (context, index) {
                        final person = people[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: KinlyAvatar(
                            name: person.name,
                            avatarBase64: person.avatar,
                            size: 42,
                          ),
                          title: Text(
                            person.name,
                            style: const TextStyle(
                              color: Tokens.textPrimary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(
                            person.deviceId,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _scanCode(BuildContext context) async {
    final strings = StringsScope.of(context);
    if (!await _ensureCamera()) {
      if (!context.mounted) return;
      _snack(context, strings.get('permissionDenied'));
      return;
    }
    if (!context.mounted) return;
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => _QrScannerPage(strings: strings),
      ),
    );
    if (raw == null || !context.mounted) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'kinly' || uri.host != 'verify') {
      _snack(context, strings.get('qrInvalid'));
      return;
    }
    final device = uri.queryParameters['device'] ?? '';
    final code = uri.queryParameters['code'] ?? '';
    final person = _controller.person(device);
    final expected = _controller.safetyCodeFor(device).replaceAll(' ', '');
    final matches = expected.isNotEmpty && expected == code.replaceAll(' ', '');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Tokens.surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusLarge),
        ),
        title: Text(
          person?.name ?? strings.get('scanTitle'),
          style: const TextStyle(
            color: Tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (person == null)
              Text(
                strings.get('qrVerified'),
                style: const TextStyle(
                  color: Tokens.textSecondary,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              )
            else
              Row(
                children: [
                  Icon(
                    matches
                        ? Icons.verified_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: matches ? Tokens.success : Tokens.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      matches
                          ? strings.get('sharedCodeBody')
                          : strings.get('qrInvalid'),
                      style: TextStyle(
                        color: matches ? Tokens.success : Tokens.danger,
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            SelectableText(
              code,
              style: const TextStyle(
                color: Tokens.textPrimary,
                fontSize: 13,
                fontFamily: 'monospace',
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!context.mounted) return;
              Navigator.of(context).pop();
              _snack(context, strings.get('codeCopied'));
            },
            child: Text(
              strings.get('copy'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              strings.get('close'),
              style: const TextStyle(color: Tokens.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _readText(BuildContext context) async {
    final strings = StringsScope.of(context);
    if (!await _ensureCamera()) {
      if (!context.mounted) return;
      _snack(context, strings.get('permissionDenied'));
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );
    if (picked == null || !context.mounted) return;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: Tokens.surfaceHigh,
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text(
                strings.get('recognizingText'),
                style: const TextStyle(color: Tokens.textPrimary),
              ),
            ],
          ),
        ),
      );
      final result = await recognizer.processImage(
        InputImage.fromFilePath(picked.path),
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final text = result.text.trim();
      if (text.isEmpty) {
        _snack(context, strings.get('noTextFound'));
        return;
      }
      await _showTextResult(context, text);
    } catch (error) {
      if (!context.mounted) return;
      Navigator.of(context).maybePop();
      _snack(context, '${strings.get('error')}: $error');
    } finally {
      await recognizer.close();
    }
  }

  Future<void> _showTextResult(BuildContext context, String text) {
    final strings = StringsScope.of(context);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.sizeOf(context).height * 0.72,
        decoration: const BoxDecoration(
          color: Tokens.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Tokens.textMuted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.get('ocrTitle'),
                        style: const TextStyle(
                          color: Tokens.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    NeuIconButton(
                      icon: Icons.copy_rounded,
                      size: 44,
                      iconSize: 18,
                      tooltip: strings.get('copyText'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: text));
                        if (!context.mounted) return;
                        _snack(context, strings.get('copied'));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Neu(
                    inset: true,
                    padding: const EdgeInsets.all(14),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        text,
                        style: const TextStyle(
                          color: Tokens.textPrimary,
                          fontSize: 14,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = StringsScope.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final photo = _photo;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
        children: [
          Text(
            strings.get('camera'),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          if (photo == null)
            GestureDetector(
              onTap: () => _takePhoto(context),
              child: Neu(
                height: 240,
                inset: true,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.photo_camera_rounded,
                      size: 42,
                      color: accent,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _busy
                          ? strings.get('starting')
                          : strings.get('takePhoto'),
                      style: const TextStyle(
                        color: Tokens.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.radiusLarge),
              child: Image.file(
                File(photo.path),
                height: 330,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: AccentButton(
                    label: strings.get('retake'),
                    icon: Icons.refresh_rounded,
                    expand: true,
                    onPressed: () => setState(() => _photo = null),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AccentButton(
                    label: strings.get('sendPhoto'),
                    icon: Icons.send_rounded,
                    expand: true,
                    onPressed: () => _sendPhoto(context),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Neu(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                _ActionRow(
                  icon: Icons.qr_code_scanner_rounded,
                  title: strings.get('scanQr'),
                  subtitle: strings.get('scanQrBody'),
                  onTap: () => _scanCode(context),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 58,
                  color: withOpacity(Colors.white, 0.04),
                ),
                _ActionRow(
                  icon: Icons.text_fields_rounded,
                  title: strings.get('ocrTitle'),
                  subtitle: strings.get('ocrBody'),
                  onTap: () => _readText(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tokens.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Tokens.textMuted),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Tokens.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Tokens.textMuted,
                      fontSize: 10.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Tokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen camera that reads the first QR code and returns its text.
class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage({required this.strings});

  final Strings strings;

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            MobileScanner(
              onDetect: (capture) {
                if (_done || !mounted) return;
                String? raw;
                for (final barcode in capture.barcodes) {
                  final value = barcode.rawValue;
                  if (value != null && value.isNotEmpty) {
                    raw = value;
                    break;
                  }
                }
                if (raw == null) return;
                _done = true;
                Navigator.of(context).pop(raw);
              },
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  NeuIconButton(
                    icon: Icons.close_rounded,
                    size: 44,
                    iconSize: 20,
                    tooltip: widget.strings.get('closeCamera'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.strings.get('scanQr'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
