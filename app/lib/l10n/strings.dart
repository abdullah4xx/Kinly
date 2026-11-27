import 'package:flutter/widgets.dart';

/// Every user-visible string in the app, in English and Arabic.
///
/// The UI mirrors layout in RTL; the language is stored locally and never sent
/// to other devices.
class Strings {
  const Strings(this.language);

  final String language;

  bool get isArabic => language == 'ar';

  static const _values = <String, ({String en, String ar})>{
    'appName': (en: 'Kinly', ar: 'كينلي'),
    'tagline': (en: 'Family chat, no internet', ar: 'دردشة العائلة، بدون إنترنت'),
    'welcomeTitle': (en: 'Welcome to Kinly', ar: 'أهلاً بك في كينلي'),
    'welcomeBody': (
      en: 'Chat with your family over Wi-Fi or a hotspot. No servers, no internet, end-to-end encrypted.',
      ar: 'تواصل مع عائلتك عبر الواي فاي أو نقطة الاتصال. بدون خوادم أو إنترنت، ومشفّر من الطرف إلى الطرف.',
    ),
    'nameLabel': (en: 'Your name', ar: 'اسمك'),
    'nameHint': (en: 'e.g. Abdullah', ar: 'مثال: عبدالله'),
    'nameEmpty': (en: 'Enter a name first', ar: 'أدخل اسمًا أولاً'),
    'nameTaken': (en: 'This name is already used by someone here', ar: 'هذا الاسم مستخدم بالفعل من شخص على الشبكة'),
    'nameTakenLong': (
      en: 'Another device on the network already uses this name. Pick a different one.',
      ar: 'هناك جهاز آخر على الشبكة يستخدم هذا الاسم. اختر اسمًا آخر.',
    ),
    'photoOptional': (en: 'Add a photo (optional)', ar: 'أضف صورة (اختياري)'),
    'changePhoto': (en: 'Change photo', ar: 'تغيير الصورة'),
    'removePhoto': (en: 'Remove photo', ar: 'إزالة الصورة'),
    'enter': (en: 'Enter', ar: 'دخول'),
    'chats': (en: 'Chats', ar: 'الدردشات'),
    'search': (en: 'Search people or messages', ar: 'ابحث عن شخص أو رسالة'),
    'noPeople': (en: 'No one here yet', ar: 'لا يوجد أحد بعد'),
    'noPeopleBody': (
      en: 'Make sure the other device is on the same Wi-Fi or hotspot with Kinly open.',
      ar: 'تأكد أن الجهاز الآخر على نفس شبكة الواي فاي أو نقطة الاتصال مع فتح كينلي.',
    ),
    'online': (en: 'online', ar: 'متصل'),
    'offline': (en: 'offline', ar: 'غير متصل'),
    'typing': (en: 'Typing...', ar: 'يكتب...'),
    'lastSeen': (en: 'last seen', ar: 'آخر ظهور'),
    'today': (en: 'Today', ar: 'اليوم'),
    'yesterday': (en: 'Yesterday', ar: 'أمس'),
    'yesterdayShort': (en: 'Yesterday', ar: 'أمس'),
    'messageHint': (en: 'Message', ar: 'رسالة'),
    'attachFile': (en: 'Send a file', ar: 'إرسال ملف'),
    'visibility': (en: 'Visible to them', ar: 'ظاهر له'),
    'hidden': (en: 'Hidden', ar: 'مخفي'),
    'hiddenFromYou': (en: 'They hid from you', ar: 'هو مخفي عنك'),
    'hideHint': (
      en: 'When off, you disappear from their list and they cannot see your messages.',
      ar: 'عند الإغلاق، تختفي من قائمته ولا يستطيع رؤية رسائلك.',
    ),
    'appearance': (en: 'Appearance', ar: 'المظهر'),
    'accentColor': (en: 'Accent color', ar: 'اللون المميز'),
    'accentBody': (
      en: 'One color drives buttons, sent bubbles and badges. It is stored on this device only.',
      ar: 'لون واحد يتحكم في الأزرار والفقاعات المرسلة والشارات. يُحفظ على هذا الجهاز فقط.',
    ),
    'colorTooClose': (
      en: 'This color is too close to the background. Pick a brighter one.',
      ar: 'هذا اللون قريب جدًا من الخلفية. اختر لونًا أفتح.',
    ),
    'preview': (en: 'Preview', ar: 'معاينة'),
    'save': (en: 'Save', ar: 'حفظ'),
    'cancel': (en: 'Cancel', ar: 'إلغاء'),
    'settings': (en: 'Settings', ar: 'الإعدادات'),
    'profile': (en: 'Profile', ar: 'الملف الشخصي'),
    'name': (en: 'Name', ar: 'الاسم'),
    'language': (en: 'Language', ar: 'اللغة'),
    'english': (en: 'English', ar: 'English'),
    'arabic': (en: 'العربية', ar: 'العربية'),
    'reduceMotion': (en: 'Reduce motion', ar: 'تقليل الحركة'),
    'reduceMotionBody': (
      en: 'Disable transitions and animated details.',
      ar: 'إيقاف الانتقالات والتفاصيل المتحركة.',
    ),
    'security': (en: 'Security', ar: 'الأمان'),
    'fingerprint': (en: 'Security code', ar: 'رمز الأمان'),
    'fingerprintBody': (
      en: 'Compare this code with the other person to verify the encrypted connection.',
      ar: 'قارن هذا الرمز مع الشخص الآخر للتحقق من الاتصال المشفّر.',
    ),
    'hiddenPeople': (en: 'People you hid', ar: 'الأشخاص الذين أخفيتهم'),
    'noHiddenPeople': (en: 'No one is hidden right now.', ar: 'لا يوجد أحد مخفي الآن.'),
    'notifications': (en: 'Notifications', ar: 'الإشعارات'),
    'about': (en: 'About', ar: 'حول'),
    'version': (en: 'Version', ar: 'الإصدار'),
    'aboutBody': (
      en: 'Kinly is an offline chat app for families. Messages, files and calls stay on the local network.',
      ar: 'كينلي تطبيق دردشة للعائلة يعمل بدون إنترنت. الرسائل والملفات والمكالمات تبقى على الشبكة المحلية.',
    ),
    'quit': (en: 'Quit', ar: 'خروج'),
    'quitBody': (en: 'Stop the node and close Kinly.', ar: 'إيقاف العقدة وإغلاق كينلي.'),
    'deleteIdentity': (en: 'Delete this device identity', ar: 'حذف هوية هذا الجهاز'),
    'deleteIdentityBody': (
      en: 'Messages and the identity on this device are erased. This cannot be undone.',
      ar: 'تُمسح الرسائل والهوية من هذا الجهاز. لا يمكن التراجع.',
    ),
    'delete': (en: 'Delete', ar: 'حذف'),
    'scan': (en: 'Verify', ar: 'تحقق'),
    'scanBody': (
      en: 'Scan this code with the other device, or compare the numbers.',
      ar: 'امسح هذا الرمز بالجهاز الآخر، أو قارن الأرقام.',
    ),
    'scanTitle': (en: 'Security code', ar: 'رمز الأمان'),
    'close': (en: 'Close', ar: 'إغلاق'),
    'retry': (en: 'Retry', ar: 'إعادة المحاولة'),
    'sending': (en: 'Sending', ar: 'جارٍ الإرسال'),
    'sent': (en: 'Sent', ar: 'أُرسلت'),
    'delivered': (en: 'Delivered', ar: 'وصلت'),
    'read': (en: 'Read', ar: 'قُرئت'),
    'failed': (en: 'Failed', ar: 'فشلت'),
    'queued': (en: 'Queued', ar: 'بالانتظار'),
    'file': (en: 'File', ar: 'ملف'),
    'fileSending': (en: 'Sending file', ar: 'جارٍ إرسال الملف'),
    'fileReceiving': (en: 'Receiving file', ar: 'جارٍ استلام الملف'),
    'fileSaved': (en: 'File saved', ar: 'تم حفظ الملف'),
    'fileFailed': (en: 'File transfer failed', ar: 'فشل نقل الملف'),
    'cancelTransfer': (en: 'Cancel', ar: 'إلغاء'),
    'photo': (en: 'Photo', ar: 'صورة'),
    'permissionDenied': (en: 'Permission denied', ar: 'تم رفض الإذن'),
    'error': (en: 'Something went wrong', ar: 'حدث خطأ ما'),
    'startError': (
      en: 'Kinly could not start the local node. Restart the app and try again.',
      ar: 'لم يستطع كينلي تشغيل العقدة المحلية. أعد تشغيل التطبيق وحاول مجددًا.',
    ),
    'starting': (en: 'Starting Kinly...', ar: 'جارٍ تشغيل كينلي...'),
    'you': (en: 'You', ar: 'أنت'),
    'onlineNow': (en: 'Online now', ar: 'متصل الآن'),
    'saveFailed': (en: 'Could not save the change', ar: 'تعذّر حفظ التغيير'),
    'copied': (en: 'Copied', ar: 'تم النسخ'),
    'tapToCopy': (en: 'Tap to copy', ar: 'اضغط للنسخ'),
    'notificationsDisabled': (en: 'Notifications are off', ar: 'الإشعارات متوقفة'),
    'call': (en: 'Call', ar: 'اتصال'),
    'voiceCall': (en: 'Voice call', ar: 'مكالمة صوتية'),
    'videoCall': (en: 'Video call', ar: 'مكالمة فيديو'),
    'calling': (en: 'Calling...', ar: 'جارٍ الاتصال...'),
    'connecting': (en: 'Connecting...', ar: 'جارٍ التوصيل...'),
    'incomingCall': (en: 'Incoming call', ar: 'مكالمة واردة'),
    'inCall': (en: 'On call', ar: 'في المكالمة'),
    'callFailed': (en: 'Call failed', ar: 'فشلت المكالمة'),
    'accept': (en: 'Accept', ar: 'قبول'),
    'decline': (en: 'Decline', ar: 'رفض'),
    'endCall': (en: 'End call', ar: 'إنهاء المكالمة'),
    'mute': (en: 'Mute', ar: 'كتم الصوت'),
    'unmute': (en: 'Unmute', ar: 'إلغاء الكتم'),
    'flipCamera': (en: 'Switch camera', ar: 'تبديل الكاميرا'),
    'youHidThem': (en: 'You hid this person', ar: 'أنت أخفيت هذا الشخص'),
    'theyHidYou': (en: 'This person hid from you', ar: 'هذا الشخص أخفى نفسه عنك'),
    'hiddenChatNotice': (
      en: 'This conversation is hidden on the other side until they write to you or you turn visibility on again.',
      ar: 'هذه المحادثة مخفية عند الطرف الآخر حتى يكتب لك أو تعيد تشغيل الظهور.',
    ),
    'now': (en: 'now', ar: 'الآن'),
    'minuteAgo': (en: 'm', ar: 'د'),
    'hourAgo': (en: 'h', ar: 'س'),
    'dayAgo': (en: 'd', ar: 'ي'),
    'ackedNameTaken': (en: 'Name rejected by the other device', ar: 'رفض الجهاز الآخر الاسم'),
    'retryName': (en: 'Choose another name', ar: 'اختر اسمًا آخر'),
    'reduceMotionOn': (en: 'Motion reduced', ar: 'تم تقليل الحركة'),
    'voiceNoteSoon': (
      en: 'Voice messages are not available yet',
      ar: 'الرسائل الصوتية غير متاحة بعد',
    ),
    'attachPhoto': (en: 'Send a photo', ar: 'إرسال صورة'),
    'verifyPerson': (en: 'Verify a person', ar: 'تحقق من شخص'),
    'thisDevice': (en: 'This device', ar: 'هذا الجهاز'),
    'deviceFingerprint': (en: 'Device fingerprint', ar: 'بصمة الجهاز'),
    'sharedCode': (en: 'Shared security code', ar: 'رمز الأمان المشترك'),
    'sharedCodeBody': (
      en: 'Both devices show the same 60 digits. Compare them in person, or scan the code.',
      ar: 'يعرض الجهازان نفس الستين رقمًا. قارنها وجهًا لوجه، أو امسح الرمز.',
    ),
    'copy': (en: 'Copy', ar: 'نسخ'),
    'codeCopied': (en: 'Code copied', ar: 'تم نسخ الرمز'),
    'noPeopleToVerify': (
      en: 'No one to verify yet',
      ar: 'لا يوجد أحد للتحقق منه بعد',
    ),
    'changeName': (en: 'Change name', ar: 'تغيير الاسم'),
    'customColor': (en: 'Custom color', ar: 'لون مخصص'),
    'hue': (en: 'Hue', ar: 'درجة اللون'),
    'saturation': (en: 'Saturation', ar: 'التشبع'),
    'messageCopied': (en: 'Message copied', ar: 'تم نسخ الرسالة'),
    'noMessages': (en: 'Say hello', ar: 'قل مرحبًا'),
    'noMessagesBody': (
      en: 'Messages are end-to-end encrypted and never leave your local network.',
      ar: 'الرسائل مشفّرة من الطرف إلى الطرف ولا تغادر شبكتك المحلية.',
    ),
    'showMeAgain': (en: 'Show me again', ar: 'أظهرني مرة أخرى'),
    'batteryTitle': (en: 'Battery optimization', ar: 'تحسين البطارية'),
    'batteryBody': (
      en: 'Allow Kinly to keep receiving messages while it is in the background.',
      ar: 'اسمح لكينلي باستقبال الرسائل أثناء عمله في الخلفية.',
    ),
    'madeBy': (en: 'Made by Abdullah', ar: 'صنعه عبدالله'),
    'checkUpdates': (en: 'Check for updates', ar: 'التحقق من التحديثات'),
    'checkingUpdates': (en: 'Checking GitHub...', ar: 'جارٍ التحقق من GitHub...'),
    'upToDate': (en: 'You have the latest version', ar: 'لديك أحدث إصدار'),
    'updateAvailable': (en: 'Update available', ar: 'يوجد تحديث'),
    'updateAvailableBody': (
      en: 'Kinly {version} is ready to download.',
      ar: 'كينلي {version} جاهز للتنزيل.',
    ),
    'updateFailed': (en: 'Update check failed', ar: 'فشل التحقق من التحديث'),
    'download': (en: 'Download', ar: 'تنزيل'),
    'later': (en: 'Later', ar: 'لاحقًا'),
    'deleteConfirmTitle': (en: 'Delete this identity?', ar: 'حذف هذه الهوية؟'),
    'quitConfirmTitle': (en: 'Close Kinly?', ar: 'إغلاق كينلي؟'),
    // Settings hub and the focused pages.
    'account': (en: 'Account', ar: 'الحساب'),
    'accountBody': (
      en: 'Profile, name, photo, language, security and app lock.',
      ar: 'الملف الشخصي والاسم والصورة واللغة والأمان وقفل التطبيق.',
    ),
    'appearanceBody': (
      en: 'Accent color, chat wallpaper and motion.',
      ar: 'اللون المميز وخلفية المحادثات والحركة.',
    ),
    'peopleBody': (
      en: 'Everyone on your network and who can see you.',
      ar: 'كل من على شبكتك ومن يستطيع رؤيتك.',
    ),
    'notificationsBody': (
      en: 'Control background receiving and the silent notification.',
      ar: 'تحكم في استقبال الرسائل في الخلفية والإشعار الصامت.',
    ),
    'updates': (en: 'Updates', ar: 'التحديثات'),
    'danger': (en: 'Danger zone', ar: 'منطقة الخطر'),
    'updatesBody': (
      en: 'Check, download and install a new version.',
      ar: 'تحقق من إصدار جديد ونزّله وثبّته.',
    ),
    'aboutBodySettings': (
      en: 'Version, source code and who made Kinly.',
      ar: 'الإصدار والشيفرة المصدرية ومن صنع كينلي.',
    ),
    'dangerBody': (
      en: 'Delete this device identity or quit the app.',
      ar: 'احذف هوية هذا الجهاز أو أغلق التطبيق.',
    ),
    'appLock': (en: 'App lock', ar: 'قفل التطبيق'),
    'appLockBody': (
      en: 'Ask for your fingerprint or device PIN before Kinly opens.',
      ar: 'اطلب بصمة إصبعك أو رمز الجهاز قبل فتح كينلي.',
    ),
    'appLockTitle': (en: 'Unlock Kinly', ar: 'فتح كينلي'),
    'appLockSubtitle': (
      en: 'Use your fingerprint or device PIN.',
      ar: 'استخدم بصمة إصبعك أو رمز الجهاز.',
    ),
    'unlock': (en: 'Unlock', ar: 'فتح'),
    'unlockWithFingerprint': (
      en: 'Unlock with fingerprint',
      ar: 'الفتح بالبصمة',
    ),
    'usePin': (en: 'Use device PIN', ar: 'استخدام رمز الجهاز'),
    'lockFailed': (
      en: 'Could not unlock. Try again.',
      ar: 'تعذّر الفتح. حاول مجددًا.',
    ),
    'noBiometrics': (
      en: 'No fingerprint or device PIN is set. Set one in Android settings, or turn the app lock off.',
      ar: 'لا توجد بصمة أو رمز جهاز مسجّل. سجّله من إعدادات أندرويد، أو أوقف قفل التطبيق.',
    ),
    'appLockUnavailable': (
      en: 'This device cannot use the app lock.',
      ar: 'هذا الجهاز لا يدعم قفل التطبيق.',
    ),
    'disableLock': (en: 'Turn off app lock', ar: 'إيقاف قفل التطبيق'),
    'appLockEnabled': (en: 'App lock is on', ar: 'قفل التطبيق مفعّل'),
    'backgroundReceive': (
      en: 'Receive messages in background',
      ar: 'استقبال الرسائل في الخلفية',
    ),
    'backgroundReceiveBody': (
      en: 'Kinly shows a silent notification and keeps receiving while closed.',
      ar: 'يعرض كينلي إشعارًا صامتًا ويستمر في الاستقبال أثناء الإغلاق.',
    ),
    'backgroundReceiveOff': (
      en: 'When off, messages arrive only while Kinly is open. Android requires the silent notification for background delivery.',
      ar: 'عند الإيقاف، تصل الرسائل فقط أثناء فتح كينلي. أندرويد يفرض الإشعار الصامت لاستقبال الرسائل في الخلفية.',
    ),
    'onlyOnThisDevice': (
      en: 'Only on this device',
      ar: 'على هذا الجهاز فقط',
    ),
    'visibleToThem': (en: 'Visible to them', ar: 'ظاهر له'),
    'people': (en: 'People', ar: 'الأشخاص'),
    'allPeople': (en: 'Everyone here', ar: 'كل الموجودين'),
    'camera': (en: 'Camera', ar: 'الكاميرا'),
    'takePhoto': (en: 'Take a photo', ar: 'التقط صورة'),
    'chooseRecipient': (en: 'Send to', ar: 'أرسل إلى'),
    'sendPhoto': (en: 'Send photo', ar: 'إرسال الصورة'),
    'retake': (en: 'Retake', ar: 'إعادة التصوير'),
    'photoSent': (en: 'Photo sent', ar: 'تم إرسال الصورة'),
    'cameraFailed': (
      en: 'Could not open the camera.',
      ar: 'تعذّر فتح الكاميرا.',
    ),
    'scanQr': (en: 'Scan a code', ar: 'مسح رمز'),
    'scanQrBody': (
      en: 'Point the camera at another device’s Kinly code.',
      ar: 'وجّه الكاميرا نحو رمز كينلي على الجهاز الآخر.',
    ),
    'qrInvalid': (
      en: 'This is not a Kinly code.',
      ar: 'هذا ليس رمز كينلي.',
    ),
    'qrVerified': (
      en: 'Code read. Compare the numbers with the other person.',
      ar: 'تم قراءة الرمز. قارن الأرقام مع الشخص الآخر.',
    ),
    'ocrTitle': (en: 'Read text from a photo', ar: 'قراءة نص من صورة'),
    'ocrBody': (
      en: 'Take a photo of a page, then select and copy the text.',
      ar: 'التقط صورة لصفحة، ثم حدّد النص وانسخه.',
    ),
    'recognizingText': (en: 'Reading text…', ar: 'جارٍ قراءة النص…'),
    'noTextFound': (
      en: 'No readable text was found.',
      ar: 'لم يتم العثور على نص مقروء.',
    ),
    'selectAll': (en: 'Select all', ar: 'تحديد الكل'),
    'copyText': (en: 'Copy text', ar: 'نسخ النص'),
    'closeCamera': (en: 'Close camera', ar: 'إغلاق الكاميرا'),
    'wallpaper': (en: 'Chat wallpaper', ar: 'خلفية المحادثات'),
    'wallpaperBody': (
      en: 'Pick a pattern that follows the accent color, or a photo from your gallery.',
      ar: 'اختر نقشًا يتبع اللون المميز، أو صورة من معرضك.',
    ),
    'wallpaperDefault': (en: 'Default', ar: 'الافتراضي'),
    'wallpaperNone': (en: 'None', ar: 'بدون'),
    'wallpaperCustom': (en: 'Photo from gallery', ar: 'صورة من المعرض'),
    'chatWallpaper': (en: 'This chat’s wallpaper', ar: 'خلفية هذه المحادثة'),
    'useDefaultWallpaper': (en: 'Use the default', ar: 'استخدام الافتراضي'),
    'removeWallpaper': (en: 'Remove wallpaper', ar: 'إزالة الخلفية'),
    'downloading': (en: 'Downloading', ar: 'جارٍ التنزيل'),
    'verifying': (en: 'Verifying…', ar: 'جارٍ التحقق…'),
    'readyToInstall': (en: 'Ready to install', ar: 'جاهز للتثبيت'),
    'installing': (en: 'Opening the installer…', ar: 'جارٍ فتح المثبّت…'),
    'installUpdate': (en: 'Install update', ar: 'تثبيت التحديث'),
    'cancelDownload': (en: 'Cancel download', ar: 'إلغاء التنزيل'),
    'downloadFailed': (en: 'Download failed', ar: 'فشل التنزيل'),
    'verifyFailed': (
      en: 'The downloaded file is damaged or incorrect.',
      ar: 'الملف الذي تم تنزيله تالف أو غير صحيح.',
    ),
    'installPermission': (
      en: 'Allow Kinly to install apps, then tap install again.',
      ar: 'اسمح لكينلي بتثبيت التطبيقات، ثم اضغط تثبيت مرة أخرى.',
    ),
    'releaseNotes': (en: 'What is new', ar: 'الجديد'),
    'latestVersion': (en: 'Latest version', ar: 'أحدث إصدار'),
    'currentVersion': (en: 'Installed version', ar: 'الإصدار المثبّت'),
    'noAnswer': (en: 'No answer', ar: 'لا يوجد رد'),
    'peerBusy': (en: 'The other person is on another call', ar: 'الشخص الآخر في مكالمة أخرى'),
    'peerOffline': (en: 'The other person is offline', ar: 'الشخص الآخر غير متصل'),
    'callEnded': (en: 'Call ended', ar: 'انتهت المكالمة'),
    'switchCamera': (en: 'Switch camera', ar: 'تبديل الكاميرا'),
    'speaker': (en: 'Speaker', ar: 'السماعة الخارجية'),
    'earpiece': (en: 'Earpiece', ar: 'سماعة الأذن'),
    'cameraOff': (en: 'Camera off', ar: 'الكاميرا مغلقة'),
    'callPermissions': (
      en: 'Kinly needs the microphone and camera for calls.',
      ar: 'يحتاج كينلي إلى الميكروفون والكاميرا للمكالمات.',
    ),
    'backgroundReceiveOn': (
      en: 'Background receiving is on',
      ar: 'استقبال الخلفية مفعّل',
    ),
  };

  String get(String key) {
    final value = _values[key];
    if (value == null) return key;
    return isArabic ? value.ar : value.en;
  }

  /// Every key the app knows about. Used by tests to check both languages.
  static Iterable<String> get keys => _values.keys;

  String get appName => get('appName');

  TextDirection get direction => isArabic ? TextDirection.rtl : TextDirection.ltr;

  Locale get locale => Locale(language);
}

/// Makes the current [Strings] available to widgets.
class StringsScope extends InheritedWidget {
  const StringsScope({super.key, required this.strings, required super.child});

  final Strings strings;

  static Strings of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StringsScope>();
    return scope?.strings ?? const Strings('en');
  }

  @override
  bool updateShouldNotify(StringsScope oldWidget) =>
      oldWidget.strings.language != strings.language;
}
