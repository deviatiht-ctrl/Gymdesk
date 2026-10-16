import type { EmailJob } from './handler.ts';

const escape = (value: unknown) => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
const line = (value: unknown) => String(value ?? '').replace(/[\r\n]/g, ' ').slice(0, 200);

export function renderEmail(job: EmailJob, logoUrl: string | null, receiptUrl: string | null = null) {
  const p = job.payload;
  const platform = job.kind === 'gym_welcome';
  const brand = platform ? 'GymDesk' : String(p.gym_name ?? 'Votre salle de sport');
  const color = !platform && /^#[0-9a-f]{6}$/i.test(String(p.accent_color)) ? String(p.accent_color) : '#0F766E';

  const date = (value: unknown) => {
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(value ?? ''));
    return m ? `${m[3]}/${m[2]}/${m[1]}` : value;
  };
  const money = (amount: unknown, currency: unknown) => `${amount ?? 0} ${currency ?? 'USD'}`;
  // Lang manm yo (gyms.settings.member_language). Sèlman rapèl yo tradui pou
  // kounye a; lòt imèl yo rete an fransè pou pa melanje lang nan yon mesaj.
  const lang = (job.kind === 'renewal_reminder' || job.kind === 'payment_receipt')
    && (p.language === 'ht' || p.language === 'en') ? p.language : 'fr';
  const t = (fr: string, ht: string, en: string) => lang === 'ht' ? ht : lang === 'en' ? en : fr;

  let title = 'Bienvenue dans votre salle';
  let subject = '';
  let intro = '';
  let note = '';
  let rows: [string, unknown][] = [];

  if (job.kind === 'gym_welcome') {
    title = 'Bienvenue sur GymDesk';
    intro = 'Merci d’avoir choisi GymDesk. Votre espace est prêt : vous pouvez gérer vos membres, les accès par empreinte et vos encaissements.';
    rows = [
      ['Salle', p.gym_name],
      ['Offre choisie', p.plan_name],
      ['Tarif', p.price == null ? 'Selon contrat' : money(p.price, p.currency ?? 'USD')],
      ['Quota', p.badge_quota ?? p.max_members],
      ['Statut', p.status === 'trial' ? 'Période d’essai (7 jours)' : 'Compte actif'],
    ];
  } else if (job.kind === 'member_welcome') {
    const startStr = date(p.start_date);
    const endStr = date(p.end_date);
    title = 'Votre inscription est confirmée';
    subject = 'Confirmation de votre inscription';
    intro = p.imported
      ? 'Merci de faire partie de notre salle. Votre dossier et votre période déjà réglée ont été repris, sans nouveaux frais d’inscription.'
      : `Bienvenue chez ${brand} ! Votre inscription a bien été enregistrée. Voici le récapitulatif de votre abonnement.`;
    rows = [
      ['Numéro de membre', p.member_number],
      ['Formule', p.plan_name],
      ['Début', startStr],
      ['Fin', endStr],
      ['Montant réglé', p.imported ? 'Période déjà réglée' : money(p.price, p.currency)],
      ['Statut', p.status === 'pending' ? 'En attente de validation' : 'Actif'],
    ];
    note = `Rappel : Votre abonnement débutera officiellement le ${startStr}. Veuillez vous présenter à la salle à cette date, car c'est à ce moment que votre période d'accès commencera à être décomptée. Pour entrer, posez simplement votre doigt sur le lecteur à l’entrée.`;
  } else if (job.kind === 'member_renewal') {
    title = 'Votre renouvellement est confirmé';
    subject = 'Renouvellement de votre abonnement';
    intro = `Merci pour votre fidélité ! Votre abonnement chez ${brand} a bien été renouvelé.`;
    rows = [
      ['Numéro de membre', p.member_number],
      ['Formule', p.plan_name],
      ['Nouvelle période', `du ${date(p.start_date)} au ${date(p.end_date)}`],
      ['Montant réglé', money(p.price, p.currency)],
    ];
    note = 'Votre accès par empreinte reste actif sans interruption.';
  } else if (job.kind === 'renewal_reminder') {
    const daysLeft = Number(p.days_left ?? 0);
    const end = date(p.end_date);
    if (lang === 'ht') {
      title = daysLeft === 0 ? 'Abònman w fini jodi a' : `Abònman w ap fini nan ${daysLeft} jou`;
      intro = daysLeft === 0
        ? `Abònman w lan nan ${brand} fini jodi a. Pou w kontinye antre, pase nan resepsyon an pou w renouvle l.`
        : `Ti rapèl : abònman w lan nan ${brand} ap fini ${end}. Pa bliye peye pou aksè w pa koupe.`;
      rows = [['Fòmil aktyèl', p.plan_name], ['Dat li fini', end], ['Pri renouvèlman', money(p.renewal_price, p.currency)]];
      note = 'Peman nan resepsyon an : kach, MonCash, NatCash, virman oswa kat.';
    } else if (lang === 'en') {
      title = daysLeft === 0 ? 'Your membership ends today' : `Your membership ends in ${daysLeft} day${daysLeft > 1 ? 's' : ''}`;
      intro = daysLeft === 0
        ? `Your membership at ${brand} ends today. To keep your access, please renew it at the front desk.`
        : `Friendly reminder: your membership at ${brand} ends on ${end}. Don’t forget to renew so your access isn’t interrupted.`;
      rows = [['Current plan', p.plan_name], ['End date', end], ['Renewal price', money(p.renewal_price, p.currency)]];
      note = 'Pay at the front desk: cash, MonCash, NatCash, bank transfer or card.';
    } else {
      const days = `${daysLeft} jour${daysLeft > 1 ? 's' : ''}`;
      title = daysLeft === 0 ? 'Votre abonnement se termine aujourd’hui' : `Votre abonnement se termine dans ${days}`;
      intro = daysLeft === 0
        ? `Votre abonnement chez ${brand} se termine aujourd’hui. Pour garder votre accès, pensez à le renouveler à la réception.`
        : `Petit rappel : votre abonnement chez ${brand} se termine le ${end}. Pensez à le renouveler pour garder votre accès sans interruption.`;
      rows = [
        ['Formule actuelle', p.plan_name],
        ['Date de fin', end],
        ['Tarif de renouvellement', money(p.renewal_price, p.currency)],
      ];
      note = 'Paiement à la réception : espèces, MonCash, NatCash, virement ou carte.';
    }
  } else if (job.kind === 'campaign') {
    title = String(p.campaign_title || p.subject || 'Information de votre salle');
    subject = String(p.subject || title);
    intro = String(p.body_text || '');
  } else if (job.kind === 'payment_receipt') {
    const credit = Number(p.credit_amount ?? 0);
    const balance = Number(p.credit_balance ?? 0);
    if (lang === 'ht') {
      title = 'Resi peman w lan';
      subject = `Resi peman #${p.receipt_no ?? ''}`;
      intro = `Peman w lan te resevwa pa ${brand}. Ou jwenn resi PDF a nan lyen ki anba a.`;
      rows = [
        ['Nimewo resi', `#${p.receipt_no ?? ''}`],
        ['Fòmil', p.plan_name],
        ['Montan peman', money(p.amount, p.currency)],
        ['Montan ou te bay', money(p.received_amount ?? p.amount, p.currency)],
        credit > 0 ? ['Balans ki rete sou kont ou', money(credit, p.currency)] : ['', ''],
        ['Metòd peman', String(p.method ?? 'cash').toUpperCase()],
        ['Dat', date(p.paid_at)],
        balance > 0 ? ['Total balans kont ou', money(balance, p.currency)] : ['', ''],
      ];
      note = 'Kenbe resi sa a kòm prèv peman w lan.';
    } else if (lang === 'en') {
      title = 'Your payment receipt';
      subject = `Payment receipt #${p.receipt_no ?? ''}`;
      intro = `Your payment was received by ${brand}. Download the PDF receipt below.`;
      rows = [
        ['Receipt no.', `#${p.receipt_no ?? ''}`],
        ['Plan', p.plan_name],
        ['Amount paid', money(p.amount, p.currency)],
        ['Amount received', money(p.received_amount ?? p.amount, p.currency)],
        credit > 0 ? ['Credited to your balance', money(credit, p.currency)] : ['', ''],
        ['Payment method', String(p.method ?? 'cash').toUpperCase()],
        ['Date', date(p.paid_at)],
        balance > 0 ? ['Your total balance', money(balance, p.currency)] : ['', ''],
      ];
      note = 'Keep this receipt as proof of payment.';
    } else {
      title = 'Reçu de paiement';
      subject = `Reçu de paiement #${p.receipt_no ?? ''}`;
      intro = `Votre paiement a bien été reçu par ${brand}. Téléchargez le reçu PDF ci-dessous.`;
      rows = [
        ['N° de reçu', `#${p.receipt_no ?? ''}`],
        ['Formule', p.plan_name],
        ['Montant du paiement', money(p.amount, p.currency)],
        ['Montant remis', money(p.received_amount ?? p.amount, p.currency)],
        credit > 0 ? ['Crédité sur votre balance', money(credit, p.currency)] : ['', ''],
        ['Mode de règlement', String(p.method ?? 'cash').toUpperCase()],
        ['Date', date(p.paid_at)],
        balance > 0 ? ['Votre balance totale', money(balance, p.currency)] : ['', ''],
      ];
      note = 'Conservez ce reçu comme justificatif de paiement.';
    }
    rows = rows.filter(([label]) => label !== '');
  }
  const greet = p.name && !/^\s*(bonjour|bonjou|bonsoir|hello|hi|salut|cher|chère)(?![a-zà-ÿ])/i.test(intro);

  let logoHtml = '';
  if (logoUrl) {
    try {
      const url = new URL(logoUrl);
      if (url.protocol === 'https:') {
        logoHtml = `<img src="${escape(url.href)}" alt="${escape(brand)}" width="72" height="72" style="display:block;width:72px;height:72px;object-fit:contain;margin:0 auto 12px;border:0;border-radius:12px">`;
      }
    } catch {
      logoHtml = '';
    }
  }

  const details = rows.filter(([, value]) => value != null && value !== '');
  const contact = platform
    ? 'SecurGYM — Sécurité et gestion de votre gym'
    : [p.gym_phone, p.gym_address].filter(Boolean).join(' · ');
  const reply = platform
    ? 'Une question ? Répondez simplement à cet email, notre équipe vous répondra.'
    : t(`Une question ? Répondez simplement à cet email : votre message arrivera directement à ${brand}.`,
        `Ou gen yon kesyon ? Reponn imèl sa a dirèkteman : mesaj ou ap rive kay ${brand}.`,
        `Any question? Just reply to this email: your message goes straight to ${brand}.`);
  const footer = job.kind === 'campaign'
    ? `Vous recevez ce message en tant que membre de ${brand}. Pour ne plus recevoir ses annonces, répondez « STOP ».`
    : '';

  const html = `<!doctype html>
<html lang="${lang}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light">
  <title>${escape(title)}</title>
</head>
<body style="margin:0;padding:0;background:#f4f5f7;color:#1f2937;font-family:Arial,Helvetica,sans-serif">
  <div style="display:none;font-size:1px;color:#f4f5f7;line-height:1px;max-height:0px;max-width:0px;opacity:0;overflow:hidden;mso-hide:all">
    ${escape(line(intro || title))}
  </div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f5f7">
    <tr>
      <td align="center" style="padding:24px 12px">
        <table role="presentation" width="560" cellspacing="0" cellpadding="0" style="width:100%;max-width:560px;background:#ffffff;border:1px solid #e5e7eb;border-radius:12px">
          <tr><td style="height:4px;background:${color};border-radius:12px 12px 0 0;font-size:0;line-height:0">&nbsp;</td></tr>
          <tr>
            <td style="padding:28px 28px 8px;text-align:center">
              ${logoHtml}
              <div style="font-size:15px;font-weight:bold;color:#111827">${escape(brand)}</div>
            </td>
          </tr>
          <tr>
            <td style="padding:12px 28px 8px;font-size:15px;line-height:1.6;color:#374151">
              <h1 style="margin:0 0 16px;font-size:20px;line-height:1.3;color:#111827">${escape(title)}</h1>
              ${greet ? `<p style="margin:0 0 12px">${t('Bonjour', 'Bonjou', 'Hello')} ${escape(p.name)},</p>` : ''}
              <p style="margin:0 0 16px;white-space:pre-line">${escape(intro)}</p>
              ${details.length > 0 ? `
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:8px 0 16px;border:1px solid #e5e7eb;border-radius:8px">
                ${details.map(([label, value], idx) => `
                <tr>
                  <td style="padding:10px 14px;font-size:13px;color:#6b7280;${idx < details.length - 1 ? 'border-bottom:1px solid #f0f1f3;' : ''}">${escape(label)}</td>
                  <td style="padding:10px 14px;font-size:14px;font-weight:bold;color:#111827;text-align:right;${idx < details.length - 1 ? 'border-bottom:1px solid #f0f1f3;' : ''}">${escape(value)}</td>
                </tr>`).join('')}
              </table>` : ''}
              ${note ? `<p style="margin:0 0 16px;font-size:14px;color:#4b5563">${escape(note)}</p>` : ''}
              ${receiptUrl ? `
              <p style="margin:0 0 20px;text-align:center">
                <a href="${escape(receiptUrl)}" style="display:inline-block;padding:12px 28px;background:${color};color:#ffffff;font-size:14px;font-weight:bold;text-decoration:none;border-radius:8px">${escape(t('Télécharger le reçu (PDF)', 'Telechaje resi a (PDF)', 'Download receipt (PDF)'))}</a>
              </p>` : ''}
              <p style="margin:0 0 16px;font-size:14px;color:#4b5563">${escape(reply)}</p>
              <p style="margin:0 0 20px">${t('Cordialement', 'Mèsi', 'Best regards')},<br>${escape(brand)}</p>
            </td>
          </tr>
          <tr>
            <td style="padding:16px 28px 20px;border-top:1px solid #f0f1f3;text-align:center;font-size:12px;line-height:1.5;color:#9ca3af">
              ${contact ? `${escape(contact)}<br>` : ''}${footer ? `${escape(footer)}<br>` : ''}
              <div style="margin-top:8px;font-size:11px;color:#9ca3af">Système sécurisé par <a href="https://securgym.com" style="color:#ff6600;text-decoration:none;font-weight:600">SecurGYM</a> · <a href="https://securgym.com" style="color:#9ca3af;text-decoration:underline">securgym.com</a></div>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

  const rawSubject = line(subject || title);
  const cleanSubject = job.kind === 'campaign'
    ? rawSubject
    : rawSubject.toLowerCase().includes(brand.toLowerCase())
      ? rawSubject
      : `${rawSubject} – ${line(brand)}`;

  return {
    subject: cleanSubject,
    html,
    text: [
      greet ? `${t('Bonjour', 'Bonjou', 'Hello')} ${p.name},` : '',
      intro,
      details.map(([label, value]) => `${label} : ${value}`).join('\n'),
      note,
      receiptUrl ? `${t('Reçu PDF', 'Resi PDF', 'PDF receipt')} : ${receiptUrl}` : '',
      reply,
      `${t('Cordialement', 'Mèsi', 'Best regards')},\n${brand}`,
      contact,
      footer,
    ].filter(Boolean).join('\n\n'),
  };
}
