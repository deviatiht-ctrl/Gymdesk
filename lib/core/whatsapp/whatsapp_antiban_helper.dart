import 'dart:math';

/// Klas ki jere tout lojik Pwoteksyon Anti-Ban pou Kanpay WhatsApp nan SecurGYM.
///
/// Karakteristik prensipal :
/// 1. Spintax Parser : transfòme `{opsyon1|opsyon2|opsyon3}` an varyasyon o aza.
/// 2. Salitasyon & Konklizyon dinamik : varye kòmansman ak finisman mesaj yo si yo pa fikse.
/// 3. Empreinte Invisible Zero-Width Unicode (`\u200B`, `\u200C`, `\u200D`, `\uFEFF`) :
///    rann chak mesaj gen yon anprent kriptografik (hash SHA-256) 100% inik pou WhatsApp pa
///    janm detekte repetisyon menm si tèks vizib la ta sanble.
/// 4. Pacing Delays & Cool-off : reta 3.5s - 5.5s ant chak voye + ti pòz 12s chak 15 mesaj.
/// 5. Auto-Spintaxify : transfòme yon tèks senp (egz: fèmen a 4h demen) an fòma varye Anti-Ban.
class WhatsAppAntiBanHelper {
  static final Random _rng = Random();

  // Karaktè Unicode envizib pou anprent inik
  static const List<String> _zeroWidthChars = [
    '\u200B', // Zero-width space
    '\u200C', // Zero-width non-joiner
    '\u200D', // Zero-width joiner
    '\uFEFF', // Zero-width no-break space
  ];

  // Lis salitasyon natirèl an Kreyòl
  static const List<String> _greetingsHtMorning = [
    'Bonjou {nom},',
    'Bonjou pou ou {nom},',
    'Salitasyon {nom},',
    'Kouman ou ye {nom},',
    'Chè {nom},',
  ];

  static const List<String> _greetingsHtAfternoon = [
    'Bonswa {nom},',
    'Bonswa pou ou {nom},',
    'Salitasyon {nom},',
    'Kouman ou ye {nom},',
    'Chè {nom},',
  ];

  // Lis salitasyon an Franse
  static const List<String> _greetingsFr = [
    'Bonjour {nom},',
    'Bonjour à vous {nom},',
    'Cher(e) {nom},',
    'Salutations {nom},',
    'Hello {nom},',
  ];

  // Lis konklizyon amikal / pwofesyonèl an Kreyòl
  static const List<String> _closingsHt = [
    'Pase yon bon jounen !',
    'N ap tann ou avèk plezi !',
    'Kenbe fò epi rete an sante !',
    'Ak tout respè,',
    'Mèsi pou konpreyansyon w !',
    'Mèsi pou fidelite w !',
    'Bon antrenman !',
  ];

  // Lis konklizyon an Franse
  static const List<String> _closingsFr = [
    'Passez une excellente journée !',
    'Au plaisir de vous retrouver à la salle !',
    'Restez en forme et motivé(e) !',
    'Bien cordialement,',
    'Merci pour votre compréhension !',
    'Merci pour votre fidélité !',
    'Bon entraînement !',
  ];

  /// 1. SPINTAX PARSER
  /// Egzamen : `{Bonjou|Bonswa|Salitasyon} Jean, {nou kontan|se yon plezi} pou nou ekri w.`
  /// Sipòte plizyè blòk spintax nan menm tèks la.
  static String parseSpintax(String text, [Random? customRng]) {
    final rng = customRng ?? _rng;
    final regex = RegExp(r'\{([^{}]+)\}');

    String current = text;
    int iterations = 0;
    while (regex.hasMatch(current) && iterations < 10) {
      current = current.replaceAllMapped(regex, (match) {
        final inner = match.group(1) ?? '';
        final parts = inner.split('|');
        if (parts.isEmpty) return '';
        final choice = parts[rng.nextInt(parts.length)].trim();
        return choice;
      });
      iterations++;
    }
    return current;
  }

  /// 2. JENERE YON ANPRENT ENVIZIB (Zero-Width Cryptographic Micro-Fingerprint)
  /// Karaktè sa yo pa parèt nan je moun sou ekran an, men pou algoritm WhatsApp yo,
  /// yo bay chak mesaj yon hash UTF-8 konplètman inik pou evite spam detection.
  static String generateZeroWidthFingerprint([int? seed]) {
    final rng = seed != null ? Random(seed) : _rng;
    final length = 6 + rng.nextInt(6); // 6 a 11 karaktè envizib
    final buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(_zeroWidthChars[rng.nextInt(_zeroWidthChars.length)]);
    }
    return buffer.toString();
  }

  /// 3. Jwenn yon salitasyon apwopriye selon lè ak lang
  static String getRandomGreeting({
    required String memberName,
    String lang = 'ht',
    Random? customRng,
  }) {
    final rng = customRng ?? _rng;
    final isFr = lang.startsWith('fr');
    final isEn = lang.startsWith('en');

    if (isFr) {
      final tpl = _greetingsFr[rng.nextInt(_greetingsFr.length)];
      return tpl.replaceAll('{nom}', memberName);
    }
    if (isEn) {
      final list = ['Hello {nom},', 'Hi {nom},', 'Dear {nom},', 'Greetings {nom},'];
      final tpl = list[rng.nextInt(list.length)];
      return tpl.replaceAll('{nom}', memberName);
    }

    // Kreyòl : verifye si se maten oswa aprèmidi
    final hour = DateTime.now().hour;
    final list = (hour >= 12) ? _greetingsHtAfternoon : _greetingsHtMorning;
    final tpl = list[rng.nextInt(list.length)];
    return tpl.replaceAll('{nom}', memberName);
  }

  /// 4. Jwenn yon konklizyon o aza
  static String getRandomClosing({
    String lang = 'ht',
    Random? customRng,
  }) {
    final rng = customRng ?? _rng;
    final isFr = lang.startsWith('fr');
    final isEn = lang.startsWith('en');

    if (isFr) {
      return _closingsFr[rng.nextInt(_closingsFr.length)];
    }
    if (isEn) {
      final list = [
        'Have a great day!',
        'Looking forward to seeing you at the gym!',
        'Stay fit and healthy!',
        'Best regards,',
        'Thank you for your understanding!',
        'Have a great workout!',
      ];
      return list[rng.nextInt(list.length)];
    }
    return _closingsHt[rng.nextInt(_closingsHt.length)];
  }

  /// 5. TRANSFÒME YON ANONS SENP AN FÒMA SPINTAX POU ANTI-BAN (Auto-Spintaxify)
  /// Egzamen antre: "Gym nan ap femen a 4h demen se pa oraire abituelli"
  /// Sòti: "{Bonjou|Bonswa|Salitasyon} {nom},\n\n{Ti avi sa a se pou enfòme w ke|Nou pase enfòme w ke|Tanpri pran nòt ke} Gym nan ap femen a 4h demen...\n\n{Mèsi pou konpreyansyon w !|N ap tann ou pou pwochen antrenman yo !|Kenbe fò !}"
  static String autoSpintaxifyAnnouncement(String rawText, {String lang = 'ht'}) {
    final clean = rawText.trim();
    if (clean.isEmpty) return '';

    final isFr = lang.startsWith('fr');
    if (isFr) {
      return '{Bonjour|Bonjour à vous|Salutations} {nom},\n\n'
          '{Nous vous informons que|Veuillez noter que|Un petit message important :}\n'
          '$clean\n\n'
          '{Merci pour votre compréhension !|Au plaisir de vous retrouver à la salle !|Bien cordialement,}';
    }

    return '{Bonjou|Bonswa|Salitasyon} {nom},\n\n'
        '{Ti avi sa a se pou enfòme w ke|Nou pase enfòme w ke|Tanpri pran nòt ke|N ap enfòme w ke} '
        '$clean\n\n'
        '{Mèsi pou konpreyansyon w !|N ap tann ou pou pwochen antrenman yo !|Kenbe fò epi pase yon bon jounen !}';
  }

  /// 6. TRANSFÒME EPI PÈSONALIZE MESAJ LA POU YON MANM (Anti-Ban Pro)
  /// Rann chak mesaj inik sou 4 nivo :
  /// 1. Salitasyon & Konklizyon otomatik si mesaj la pa t genyen (pou mesaj custom toujou varye)
  /// 2. Ranplasman tags: {nom}, {prenom}, {gym}, {date}, {salitasyon}, {konklizyon}
  /// 3. Evalyasyon Spintax {opsyon A|opsyon B}
  /// 4. Anprent envizib zero-width micro-fingerprint pou hash SHA-256 inik
  static String humanizeMessage({
    required String body,
    required String memberName,
    required String gymName,
    String? title,
    String? footer,
    String lang = 'ht',
    int recipientIndex = 0,
    bool addZeroWidthFingerprint = true,
  }) {
    final firstName = memberName.trim().split(' ').first;
    final cleanGymName = gymName.trim().isNotEmpty ? gymName.trim() : 'SecurGYM';
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    String text = body;

    // Ranplase tags prensipal yo
    text = text
        .replaceAll('{nom}', memberName.trim())
        .replaceAll('{non}', memberName.trim())
        .replaceAll('{name}', memberName.trim())
        .replaceAll('{prenom}', firstName)
        .replaceAll('{first_name}', firstName)
        .replaceAll('{gym}', cleanGymName)
        .replaceAll('{gym_name}', cleanGymName)
        .replaceAll('{date}', dateStr);

    // Tags entèlijan pou varyasyon
    if (text.contains('{salitasyon}') || text.contains('{greeting}')) {
      final greeting = getRandomGreeting(memberName: memberName, lang: lang);
      text = text
          .replaceAll('{salitasyon}', greeting)
          .replaceAll('{greeting}', greeting);
    }

    if (text.contains('{konklizyon}') || text.contains('{closing}')) {
      final closing = getRandomClosing(lang: lang);
      text = text
          .replaceAll('{konklizyon}', closing)
          .replaceAll('{closing}', closing);
    }

    // Si se yon mesaj custom ki pa kòmanse ak yon salitasyon, ajoute yon salitasyon natirèl otomatik
    final trimmedLower = text.trim().toLowerCase();
    final hasGreeting = trimmedLower.startsWith('bonjou') ||
        trimmedLower.startsWith('bonswa') ||
        trimmedLower.startsWith('bonjour') ||
        trimmedLower.startsWith('salut') ||
        trimmedLower.startsWith('hello') ||
        trimmedLower.startsWith('hi ') ||
        trimmedLower.startsWith('salitasyon') ||
        trimmedLower.startsWith('chè') ||
        trimmedLower.startsWith('cher');

    if (!hasGreeting && !text.contains('{')) {
      final dynamicGreeting = getRandomGreeting(memberName: memberName, lang: lang);
      text = '$dynamicGreeting\n\n$text';
    }

    // Si li pa gen konklizyon, ajoute yon ti fòmil politès amikal
    final hasClosing = trimmedLower.endsWith('mèsi !') ||
        trimmedLower.endsWith('mèsi.') ||
        trimmedLower.endsWith('merci !') ||
        trimmedLower.endsWith('merci.') ||
        trimmedLower.endsWith('cordialement,') ||
        trimmedLower.endsWith('cordialement') ||
        trimmedLower.endsWith('bonne journée !') ||
        trimmedLower.endsWith('pase yon bon jounen !');

    if (!hasClosing && !text.contains('}')) {
      final dynamicClosing = getRandomClosing(lang: lang);
      text = '$text\n\n$dynamicClosing';
    }

    // Aplike Spintax
    text = parseSpintax(text);

    // Konstriksyon tit ak footer
    final titlePart = (title != null && title.trim().isNotEmpty) ? '*${title.trim()}*\n\n' : '';
    final footerPart = (footer != null && footer.isNotEmpty) ? footer : '';

    String fullMessage = '$titlePart$text$footerPart';

    // Ajoute anprent envizib zero-width pou diferansyasyon byte hash
    if (addZeroWidthFingerprint) {
      final fp1 = generateZeroWidthFingerprint(recipientIndex * 31 + DateTime.now().microsecond);
      final fp2 = generateZeroWidthFingerprint(recipientIndex * 17 + 7);
      if (fullMessage.contains('\n')) {
        final firstBreak = fullMessage.indexOf('\n');
        fullMessage = fullMessage.substring(0, firstBreak) +
            fp1 +
            fullMessage.substring(firstBreak) +
            fp2;
      } else {
        fullMessage = '$fullMessage$fp1';
      }
    }

    return fullMessage;
  }

  /// 7. KALKILE RETA ENTÈLIJAN ANT CHAK VOYE (Pacing Delay)
  /// Retounen kantite milisegonn pou tann ant voye :
  /// - Reta estanda : 3,500ms a 5,500ms (ak jitter o aza)
  /// - Si se chak 15 mesaj (index % 15 == 0) : ti pòz refwadisman 10,000ms (10 segonn)
  static Duration getPacingDelay({required int index}) {
    if (index > 0 && index % 15 == 0) {
      return const Duration(milliseconds: 10000);
    }
    final jitterMs = 3500 + _rng.nextInt(2000); // 3.5s - 5.5s
    return Duration(milliseconds: jitterMs);
  }

  /// Èske se yon pòz refwadisman apre yon blòk mesaj?
  static bool isCoolingBreak({required int index}) {
    return index > 0 && index % 15 == 0;
  }

  /// 8. JENERE EGZANP VARYASYON POU PREVIEW
  static List<String> generatePreviewVariations({
    required String body,
    required String gymName,
    String? title,
    String lang = 'ht',
    int count = 3,
  }) {
    final sampleNames = [
      'Jean Pierre',
      'Marie Flore',
      'Wisler Augustin',
      'Esther Joseph',
      'Patrick Noel',
    ];

    final variations = <String>[];
    for (int i = 0; i < count; i++) {
      final name = sampleNames[i % sampleNames.length];
      final spun = humanizeMessage(
        body: body,
        memberName: name,
        gymName: gymName,
        title: title,
        lang: lang,
        recipientIndex: i,
        addZeroWidthFingerprint: false,
      );
      variations.add(spun);
    }
    return variations;
  }
}
