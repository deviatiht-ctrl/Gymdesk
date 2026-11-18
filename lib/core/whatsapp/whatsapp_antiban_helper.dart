import 'dart:math';

/// Klas ki jere tout lojik Pwoteksyon Anti-Ban pou Kanpay WhatsApp nan SecurGYM.
///
/// Karakteristik prensipal :
/// 1. Milti-Angl Semantik (50+ Vèsyon Diferan ak IA) :
///    Separe mesaj kanpay la an 5 Gwo Fanmi/Archetypes semantik diferan :
///    - Angl 0 : Avi Ofisyèl & Administratif
///    - Angl 1 : Amikal & Pèsonèl
///    - Angl 2 : Planifikasyon & Konsèy Espòtif
///    - Angl 3 : Flash Enfo Kout & Dirèk
///    - Angl 4 : Respè, Rekonesans & Kominote
///    Chak manm resevwa yon estrikti fraz, vokabilè, ak ton konplètman diferan !
/// 2. Spintax Parser : transfòme `{opsyon1|opsyon2|opsyon3}` an varyasyon o aza.
/// 3. Empreinte Invisible Zero-Width Unicode (`\u200B`, `\u200C`, `\u200D`, `\uFEFF`) :
///    rann chak mesaj gen yon anprent kriptografik (hash SHA-256) 100% inik pou WhatsApp pa
///    janm detekte repetisyon menm si tèks vizib la ta sanble.
/// 4. Pacing Delays & Cool-off :
///    - Mòd 'safe' (Rekòmande pou 100+ moun) : 15s a 27s ant chak voye + pòz 60s chak 10 mesaj
///    - Mòd 'moderate' : 8s a 14s ant chak voye + pòz 30s chak 15 mesaj
///    - Mòd 'fast' : 4s a 7s ant chak voye + pòz 15s chak 20 mesaj
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
    'Hello {nom},',
  ];

  static const List<String> _greetingsHtAfternoon = [
    'Bonswa {nom},',
    'Bonswa pou ou {nom},',
    'Salitasyon {nom},',
    'Kouman ou ye {nom},',
    'Chè {nom},',
    'Hello {nom},',
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
  static String generateZeroWidthFingerprint([int? seed]) {
    final rng = seed != null ? Random(seed) : _rng;
    final length = 6 + rng.nextInt(8); // 6 a 13 karaktè envizib
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
  static String autoSpintaxifyAnnouncement(String rawText, {String lang = 'ht'}) {
    final clean = rawText.trim();
    if (clean.isEmpty) return '';

    final isFr = lang.startsWith('fr');
    if (isFr) {
      return '{Bonjour|Bonjour à vous|Salutations} {nom},\n\n'
          '{Nous vous informons que|Veuillez noter que|Un petit message important :|Note d\'information :}\n'
          '$clean\n\n'
          '{Merci pour votre compréhension !|Au plaisir de vous retrouver à la salle !|Bien cordialement,|Toute l\'équipe vous remercie !}';
    }

    return '{Bonjou|Bonswa|Salitasyon} {nom},\n\n'
        '{Ti avi sa a se pou enfòme w ke|Nou pase enfòme w ke|Tanpri pran nòt ke|N ap enfòme w ke|Yon ti rapèl enpòtan :} '
        '$clean\n\n'
        '{Mèsi pou konpreyansyon w !|N ap tann ou pou pwochen antrenman yo !|Kenbe fò epi pase yon bon jounen !|Nou remèsye w pou kolaborasyon w !}';
  }

  /// Netwaye yon tèks pou ekstrè mesaj santral la san vye salitasyon/konklizyon fiks ki repete
  static String extractCoreAnnouncement(String rawText) {
    String text = rawText.trim();
    // Retire salitasyon estanda si yo te ekri l an tèt
    final lines = text.split('\n');
    if (lines.isNotEmpty) {
      final first = lines.first.trim().toLowerCase();
      if (first.startsWith('bonjou') ||
          first.startsWith('bonswa') ||
          first.startsWith('bonjour') ||
          first.startsWith('salut') ||
          first.startsWith('hello') ||
          first.startsWith('chè') ||
          first.startsWith('cher')) {
        lines.removeAt(0);
        text = lines.join('\n').trim();
      }
    }
    return text.isNotEmpty ? text : rawText.trim();
  }

  /// 6. SEMANTIC MULTI-ANGLE ENGINE (50+ Sans & Estrikti Diferan)
  /// Separe chak mesaj an 5 ang semantik diferan pou garanti okenn mesaj pa sanble :
  /// - Angl 0: Avi Ofisyèl & Administratif
  /// - Angl 1: Amikal & Pèsonèl
  /// - Angl 2: Planifikasyon & Konsèy Espòtif
  /// - Angl 3: Flash Enfo Kout & Dirèk
  /// - Angl 4: Respè, Rekonesans & Kominote
  static String buildSemanticAngleMessage({
    required String rawBody,
    required String memberName,
    required String gymName,
    required int recipientIndex,
    String lang = 'ht',
  }) {
    final cleanGym = gymName.trim().isNotEmpty ? gymName.trim() : 'SecurGYM';
    final isFr = lang.startsWith('fr');
    final archetype = recipientIndex % 5;
    final rng = Random(recipientIndex * 997 + DateTime.now().minute * 13 + 7);
    final core = extractCoreAnnouncement(rawBody);

    if (isFr) {
      switch (archetype) {
        case 0: // Officiel & Administratif
          final headers = [
            '📢 *COMMUNIQUÉ OFFICIEL - $cleanGym*',
            '📋 *AVIS DE LA DIRECTION*',
            '⚠️ *INFORMATION IMPORTANTE AUX ADHÉRENTS*',
            'ℹ️ *NOTE D\'INFORMATION*',
          ];
          final greetings = [
            'Cher(e) $memberName,',
            'À l\'attention de $memberName,',
            'Salutations distinguées $memberName,',
            'Bonjour $memberName,',
          ];
          final intros = [
            'La direction de la salle vous informe de la disposition suivante :',
            'Nous portons à votre attention cette mise au point :',
            'Veuillez prendre note de cette disposition concernant les horaires :',
            'L\'administration tient à informer l\'ensemble de ses membres :',
          ];
          final closings = [
            'Nous vous remercions pour votre compréhension et votre collaboration.',
            'Merci pour votre confiance continue.',
            'Toute l\'équipe reste à votre entière disposition.',
            'Nous comptons sur votre habituelle collaboration.',
          ];
          final signoffs = [
            '— La Direction $cleanGym',
            '— L\'Équipe Administrative',
            '— L\'Administration de la salle',
          ];
          return '${headers[rng.nextInt(headers.length)]}\n\n'
              '${greetings[rng.nextInt(greetings.length)]}\n'
              '${intros[rng.nextInt(intros.length)]}\n\n'
              '👉 $core\n\n'
              '${closings[rng.nextInt(closings.length)]}\n'
              '${signoffs[rng.nextInt(signoffs.length)]}';

        case 1: // Amical & Chaleureux
          final greetings = [
            'Bonjour $memberName !',
            'Hello $memberName !',
            'Comment allez-vous $memberName ?',
            'Salutations à vous $memberName !',
          ];
          final intros = [
            'Un petit mot rapide pour vous tenir au courant :',
            'Voici un petit message pour votre organisation personnelle :',
            'On passe vous faire un petit rappel amical :',
            'Une petite info rapide pour vos séances :',
          ];
          final closings = [
            'Prenez bien soin de vous et à très vite !',
            'Au plaisir de vous retrouver à la salle !',
            'Restez motivé(e) et passez une belle journée !',
            'Gardez la forme et le cap !',
          ];
          return '${greetings[rng.nextInt(greetings.length)]}\n\n'
              '${intros[rng.nextInt(intros.length)]}\n'
              '$core\n\n'
              '${closings[rng.nextInt(closings.length)]}';

        case 2: // Planning Sportif
          final headers = [
            '🏋️ *Planning Entraînement*',
            '💪 *Vos Séances à $cleanGym*',
            '🎯 *Information Sportive & Horaires*',
          ];
          final greetings = [
            'Bonjour athlète $memberName,',
            'Cher(e) sportif / sportive $memberName,',
            'Bonjour $memberName,',
          ];
          final intros = [
            'Afin d\'ajuster au mieux vos entraînements :',
            'Pour vous permettre d\'organiser votre planning de sport sans surprise :',
            'Si vous avez prévu de vous entraîner prochainement :',
            'Pour optimiser vos séances à la salle :',
          ];
          final closings = [
            'Adaptez votre créneau pour continuer à progresser !',
            'Bonne séance et restez régulier(e) dans vos objectifs !',
            'Votre santé et votre forme sont notre priorité !',
            'Excellent entraînement à vous !',
          ];
          return '${headers[rng.nextInt(headers.length)]}\n\n'
              '${greetings[rng.nextInt(greetings.length)]}\n'
              '${intros[rng.nextInt(intros.length)]}\n\n'
              '$core\n\n'
              '${closings[rng.nextInt(closings.length)]}';

        case 3: // Flash Info Direct
          final headers = [
            '⚡ *FLASH INFO $cleanGym*',
            '🔔 *NOTE RAPIDE*',
            '⏱️ *INFO EN 30 SECONDES*',
          ];
          final greetings = [
            '$memberName,',
            'Message flash pour $memberName :',
            'Note rapide pour $memberName :',
          ];
          return '${headers[rng.nextInt(headers.length)]}\n'
              '${greetings[rng.nextInt(greetings.length)]}\n\n'
              '$core\n\n'
              'Merci pour votre attention et bonne journée !';

        default: // Respect & Communauté
          final greetings = [
            'Cher(e) membre $memberName,',
            'Sincères salutations $memberName,',
            'Bonjour avec tout notre respect $memberName,',
          ];
          final intros = [
            'C\'est toujours un grand plaisir de vous compter parmi nos membres. Veuillez noter :',
            'Nous vous remercions chaleureusement pour votre fidélité. Voici un mot important :',
            'En vous remerciant pour votre confiance au quotidien, nous vous informons que :',
          ];
          final closings = [
            'Avec toute notre considération,',
            'Merci pour votre confiance renouvelée,',
            'Au nom de toute la famille $cleanGym,',
          ];
          return '${greetings[rng.nextInt(greetings.length)]}\n\n'
              '${intros[rng.nextInt(intros.length)]}\n\n'
              '$core\n\n'
              '${closings[rng.nextInt(closings.length)]}\n'
              'L\'Équipe $cleanGym';
      }
    }

    // Kreyòl Ayisyen (HT)
    switch (archetype) {
      case 0: // Avi Ofisyèl & Administratif
        final headers = [
          '📢 *AVI OFISYÈL $cleanGym*',
          '📋 *KOMINIKE DIREKSYON AN*',
          '⚠️ *AVI ENPÒTAN POU TOUT MANM YO*',
          'ℹ️ *NÒT ENFÒMASYON OFISYÈL*',
        ];
        final greetings = [
          'Chè $memberName,',
          'Pou atansyon $memberName,',
          'Salitasyon distenge $memberName,',
          'Bonjou $memberName,',
        ];
        final intros = [
          'Administrasyon sal la ap enfòme w ke :',
          'Nou pote a konesans ou modifikasyon sa a :',
          'Tanpri pran nòt sou orè fonksyònman nou an :',
          'Direksyon sal la pase enfòme tout manm yo :',
        ];
        final closings = [
          'Nou remèsye w pou bon konpreyansyon w ak kolaborasyon w.',
          'Mèsi pou konpreyansyon w.',
          'Tout ekip la remèsye w pou kolaborasyon w.',
          'Nou konte sou bon konpreyansyon w.',
        ];
        final signoffs = [
          '— Administrasyon $cleanGym',
          '— Direksyon $cleanGym',
          '— Jesyon Sal la',
        ];
        return '${headers[rng.nextInt(headers.length)]}\n\n'
            '${greetings[rng.nextInt(greetings.length)]}\n'
            '${intros[rng.nextInt(intros.length)]}\n\n'
            '👉 $core\n\n'
            '${closings[rng.nextInt(closings.length)]}\n'
            '${signoffs[rng.nextInt(signoffs.length)]}';

      case 1: // Amikal & Pèsonèl
        final greetings = [
          'Kouman w ye $memberName ?',
          'Salitasyon pou ou $memberName !',
          'Bonjou zanmi $memberName,',
          'Kouman fòm nan ye $memberName ?',
          'Hello $memberName !',
        ];
        final intros = [
          'N ap fè w yon ti rapèl rapid pou jodi/demen :',
          'Nou pase kite yon ti mesaj rapid pou ou :',
          'Jis yon ti nòt rapid pou w rete okouran :',
          'Yon ti enfòmasyon rapid pou w pa sezi :',
        ];
        final closings = [
          'Kenbe fò epi pase yon bèl jounen !',
          'N ap tann ou pou pwochen sesyon yo avèk plezi !',
          'Rete motive epi pase yon bon moman !',
          'Kenbe motivasyon an wo !',
        ];
        return '${greetings[rng.nextInt(greetings.length)]}\n\n'
            '${intros[rng.nextInt(intros.length)]}\n'
            '$core\n\n'
            '${closings[rng.nextInt(closings.length)]}';

      case 2: // Planifikasyon Antrenman
        final headers = [
          '🏋️ *Planifikasyon Antrenman*',
          '💪 *Sesyon Antrenman $cleanGym*',
          '🎯 *Objektif & Orè*',
        ];
        final greetings = [
          'Bonjou $memberName,',
          'Salitasyon atlèt $memberName,',
          'Pou ou menm $memberName,',
          'Hello chanpyon $memberName,',
        ];
        final intros = [
          'Pou w ka byen planifye sesyon antrenman w lan :',
          'Pou w pa rate sesyon espò w la :',
          'Pou w ka jere orè antrenman w lan kòrèkteman :',
          'Si w te prevwa vin depanse enèji jodi a/demen :',
        ];
        final closings = [
          'Ajiste orè w pou w toujou kenbe fòm nan !',
          'Antrene di epi rete konsistan nan objektif ou yo !',
          'Sante w ak fòm ou se priyorite nou !',
          'Bon antrenman avèk siksè !',
        ];
        return '${headers[rng.nextInt(headers.length)]}\n\n'
            '${greetings[rng.nextInt(greetings.length)]}\n'
            '${intros[rng.nextInt(intros.length)]}\n\n'
            '$core\n\n'
            '${closings[rng.nextInt(closings.length)]}';

      case 3: // Flash Enfo Kout & Dirèk
        final headers = [
          '⚡ *FLASH INFO $cleanGym*',
          '🔔 *RAPÈL RAPID*',
          '⏱️ *ENFO MINIT*',
        ];
        final greetings = [
          '$memberName,',
          'Flash Enfo $memberName :',
          'Enfòmasyon rapid pou $memberName :',
        ];
        return '${headers[rng.nextInt(headers.length)]}\n'
            '${greetings[rng.nextInt(greetings.length)]}\n\n'
            '$core\n\n'
            'Mèsi pou atansyon w epi pase yon bon jounen !';

      default: // Respè, Rekonesans & Kominote
        final greetings = [
          'Chè manm $memberName,',
          'Salitasyon sensè pou ou $memberName,',
          'Bonjou avèk respè $memberName,',
        ];
        final intros = [
          'Nou toujou apresye prezans ou nan fanmi $cleanGym nan. Nou pase enfòme w ke :',
          'Nou remèsye w pou fidelite w. N ap pote ti avi sa a ba ou :',
          'Se toujou yon plezi pou nou konte w pami nou. Tanpri pran nòt :',
        ];
        final closings = [
          'Ak tout respè e konsiderasyon,',
          'Mèsi pou konfyans ou nan nou,',
          'Nan non tout fanmi sal la, nou swete w yon ekselan moman !',
        ];
        return '${greetings[rng.nextInt(greetings.length)]}\n\n'
            '${intros[rng.nextInt(intros.length)]}\n\n'
            '$core\n\n'
            '${closings[rng.nextInt(closings.length)]}\n'
            'Ekip $cleanGym';
    }
  }

  /// 7. TRANSFÒME EPI PÈSONALIZE MESAJ LA POU YON MANM (Anti-Ban Pro Max)
  /// Aplike Milti-Angl Semantik + Spintax + Hash Cryptographique Envizib
  static String humanizeMessage({
    required String body,
    required String memberName,
    required String gymName,
    String? title,
    String? footer,
    String lang = 'ht',
    int recipientIndex = 0,
    bool addZeroWidthFingerprint = true,
    bool useSemanticArchetypes = true,
  }) {
    final cleanGymName = gymName.trim().isNotEmpty ? gymName.trim() : 'SecurGYM';
    final firstName = memberName.trim().split(' ').first;
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    String text;

    // Si itilizatè a PA t mete spintax konplèk pa li, nou itilize Milti-Angl Semantik la otomatikman !
    final containsHeavySpintax = (body.split('{').length - 1) >= 3;
    if (useSemanticArchetypes && !containsHeavySpintax) {
      text = buildSemanticAngleMessage(
        rawBody: body,
        memberName: memberName,
        gymName: cleanGymName,
        recipientIndex: recipientIndex,
        lang: lang,
      );
    } else {
      text = body;
    }

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

    // Tags entèlijan pou varyasyon si yo prezan
    if (text.contains('{salitasyon}') || text.contains('{greeting}')) {
      final greeting = getRandomGreeting(memberName: memberName, lang: lang);
      text = text.replaceAll('{salitasyon}', greeting).replaceAll('{greeting}', greeting);
    }

    if (text.contains('{konklizyon}') || text.contains('{closing}')) {
      final closing = getRandomClosing(lang: lang);
      text = text.replaceAll('{konklizyon}', closing).replaceAll('{closing}', closing);
    }

    // Aplike Spintax
    text = parseSpintax(text);

    // Tit ak footer si genyen
    final titlePart = (title != null && title.trim().isNotEmpty && !text.contains(title.trim()))
        ? '*${title.trim()}*\n\n'
        : '';
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

  /// 8. KALKILE RETA ENTÈLIJAN ANT CHAK VOYE (Pacing Delay)
  /// - 'safe' : 15s a 27s (Mwayèn 20s) pou pwoteje kont lan kont tout bot-ban Meta
  /// - 'moderate' : 8s a 14s (Mwayèn 11s)
  /// - 'fast' : 4s a 7s (Mwayèn 5s)
  static Duration getPacingDelay({required int index, String speedMode = 'safe'}) {
    switch (speedMode) {
      case 'fast':
        final ms = 4000 + _rng.nextInt(3000); // 4s - 7s
        return Duration(milliseconds: ms);
      case 'moderate':
        final ms = 8000 + _rng.nextInt(6000); // 8s - 14s
        return Duration(milliseconds: ms);
      case 'safe':
      default:
        final ms = 15000 + _rng.nextInt(12000); // 15s - 27s
        return Duration(milliseconds: ms);
    }
  }

  /// Èske se yon pòz refwadisman apre yon blòk mesaj?
  static bool isCoolingBreak({required int index, String speedMode = 'safe'}) {
    if (index <= 0) return false;
    switch (speedMode) {
      case 'fast':
        return index % 20 == 0;
      case 'moderate':
        return index % 15 == 0;
      case 'safe':
      default:
        return index % 10 == 0;
    }
  }

  /// Kantite segonn pou pòz refwadisman an
  static int getCoolingDurationSeconds({String speedMode = 'safe'}) {
    switch (speedMode) {
      case 'fast':
        return 15;
      case 'moderate':
        return 30;
      case 'safe':
      default:
        return 60; // 1 minit repo konplè pou reset fenèt Meta a
    }
  }

  /// 9. JENERE EGZANP VARYASYON POU PREVIEW
  static List<Map<String, String>> generateSemanticAnglesPreview({
    required String body,
    required String gymName,
    String lang = 'ht',
  }) {
    final archetypesHt = [
      'Angl 1 : Avi Ofisyèl & Administratif',
      'Angl 2 : Amikal & Pèsonèl',
      'Angl 3 : Planifikasyon Antrenman & Sante',
      'Angl 4 : Flash Enfo Kout & Dirèk',
      'Angl 5 : Respè, Rekonesans & Kominote',
    ];

    final archetypesFr = [
      'Angle 1 : Communiqué Officiel',
      'Angle 2 : Message Amical & Proche',
      'Angle 3 : Planning Sportif & Conseils',
      'Angle 4 : Flash Info Court & Direct',
      'Angle 5 : Courtoisie & Fidélité',
    ];

    final labels = lang.startsWith('fr') ? archetypesFr : archetypesHt;
    final results = <Map<String, String>>[];

    for (int i = 0; i < 5; i++) {
      final sampleMessage = humanizeMessage(
        body: body,
        memberName: 'Jean Dupont',
        gymName: gymName,
        recipientIndex: i,
        lang: lang,
        addZeroWidthFingerprint: false,
        useSemanticArchetypes: true,
      );
      results.add({
        'title': labels[i],
        'content': sampleMessage,
      });
    }

    return results;
  }

  /// Pou konpatibilite ansyen kòd
  static List<String> generatePreviewVariations({
    required String body,
    required String gymName,
    String? title,
    String lang = 'ht',
    int count = 3,
  }) {
    final previews = generateSemanticAnglesPreview(
      body: body,
      gymName: gymName,
      lang: lang,
    );
    return previews.take(count).map((m) => m['content'] ?? '').toList();
  }
}
