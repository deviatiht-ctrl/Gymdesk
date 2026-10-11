import type { EmailJob } from './handler.ts';

const escape = (value: unknown) => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
const line = (value: unknown) => String(value ?? '').replace(/[\r\n]/g, ' ').slice(0, 200);

export function renderEmail(job: EmailJob, logoUrl: string | null) {
  const p = job.payload;
  const platform = job.kind === 'gym_welcome';
  const brand = platform ? 'GymDesk' : String(p.gym_name ?? 'Votre salle de sport');
  const color = !platform && /^#[0-9a-f]{6}$/i.test(String(p.accent_color)) ? String(p.accent_color) : '#0F766E';

  let title = 'Bienvenue dans votre salle';
  let intro = '';
  let note = '';
  let rows: [string, unknown][] = [];

  if (job.kind === 'gym_welcome') {
    title = 'Bienvenue sur GymDesk';
    intro = 'Merci d’avoir choisi GymDesk. Votre espace est prêt : gérez vos membres, vos empreintes biométriques et vos finances en toute sécurité.';
    rows = [
      ['Salle', p.gym_name],
      ['Offre choisie', p.plan_name],
      ['Tarif', p.price == null ? 'Selon contrat' : `${p.price} ${p.currency ?? 'USD'}`],
      ['Quota', p.badge_quota ?? p.max_members],
      ['Statut', p.status === 'trial' ? 'Période d’essai (7 jours)' : 'Compte actif'],
    ];
    note = 'Les conditions de votre offre s’appliquent. Pour toute question, contactez le support Cvisual.';
  } else if (job.kind === 'member_welcome') {
    title = 'Enregistrement Confirmé';
    intro = p.imported
      ? `Merci de faire partie de notre salle. Votre dossier et votre période déjà réglée ont été repris dans GymDesk, sans nouveaux frais d’inscription.`
      : `Bienvenue chez ${escape(brand)} ! Votre inscription a été enregistrée avec succès. Votre empreinte digitale est configurée pour un accès instantané et sécurisé aux portes.`;
    rows = [
      ['Membre', p.name],
      ['Numéro de membre', p.member_number],
      ['Formule choisie', p.plan_name],
      ['Date de début', p.start_date],
      ['Date de fin d’abonnement', p.end_date],
      ['Montant réglé', `${p.price ?? 0} ${p.currency ?? 'HTG'}`],
      ['Statut', p.imported ? 'Période déjà réglée avant la reprise' : 'Abonnement Actif'],
    ];
    note = 'Vous recevrez des alertes automatiques avant l’expiration de votre abonnement. Lors de vos visites, posez simplement votre doigt sur le lecteur biométrique.';
  } else if (job.kind === 'member_renewal') {
    title = 'Renouvellement Confirmé';
    intro = `Merci pour votre fidélité ! Votre abonnement chez ${escape(brand)} a été renouvelé avec succès.`;
    rows = [
      ['Membre', p.name],
      ['Numéro', p.member_number],
      ['Formule', p.plan_name],
      ['Nouvelle période', `${p.start_date} au ${p.end_date}`],
      ['Montant réglé', `${p.price ?? 0} ${p.currency ?? 'HTG'}`],
      ['Statut', 'Abonnement Actif'],
    ];
    note = 'Votre accès par empreinte digitale reste actif sans interruption.';
  } else if (job.kind === 'renewal_reminder') {
    const daysLeft = Number(p.days_left ?? 0);
    title = daysLeft === 0 ? 'Votre abonnement expire aujourd’hui' : `Rappel : Abonnement expire dans ${daysLeft} jour${daysLeft > 1 ? 's' : ''}`;
    intro = daysLeft === 0
      ? `Votre abonnement chez ${escape(brand)} arrive à son terme aujourd’hui. Pour éviter toute interruption de votre accès aux équipements, veuillez effectuer votre renouvellement à la réception.`
      : `Votre abonnement chez ${escape(brand)} arrive bientôt à échéance. Pensez à renouveler votre formule pour conserver votre accès fluide aux portes.`;
    rows = [
      ['Membre', p.name],
      ['Formule actuelle', p.plan_name],
      ['Date d’expiration', p.end_date],
      ['Jours restants', `${daysLeft} jour${daysLeft > 1 ? 's' : ''}`],
      ['Tarif de renouvellement', `${p.renewal_price ?? 0} ${p.currency ?? 'HTG'}`],
    ];
    note = 'Paiements acceptés à la réception : Espèces, MonCash, NatCash, Virement ou Carte. Contactez la réception dès votre prochaine visite.';
  } else if (job.kind === 'campaign') {
    title = String(p.campaign_title || p.subject || 'Annonce de votre salle');
    intro = String(p.body_text || '');
    rows = [];
    note = 'Vous recevez ce message car vous êtes membre de la salle.';
  } else if (job.kind === 'payment_receipt') {
    title = 'Reçu de Paiement';
    intro = `Votre paiement a bien été encaissé et validé par la réception de ${escape(brand)}.`;
    rows = [
      ['Membre', p.name],
      ['Montant reçu', `${p.amount ?? 0} ${p.currency ?? 'HTG'}`],
      ['Mode de règlement', String(p.method ?? 'Cash').toUpperCase()],
      ['Référence', p.reference || 'Paiement direct en caisse'],
      ['Date', p.paid_at],
    ];
    note = 'Conservez cet email comme reçu justificatif de paiement.';
  }

  let logoHtml = '';
  if (logoUrl) {
    try {
      const url = new URL(logoUrl);
      if (url.protocol === 'https:') {
        logoHtml = `<img src="${escape(url.href)}" alt="${escape(brand)}" width="96" style="display:block;max-width:96px;max-height:96px;object-fit:contain;margin:0 auto 16px;border-radius:12px">`;
      }
    } catch {
      logoHtml = '';
    }
  }

  const details = rows.filter(([, value]) => value != null && value !== '');
  const contact = platform
    ? 'GymDesk — Plateforme de gestion de salles'
    : [p.gym_phone, p.gym_address].filter(Boolean).join(' · ');

  const html = `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escape(title)}</title>
</head>
<body style="margin:0;padding:24px 12px;background:#0f172a;color:#1e293b;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif">
  <div style="display:none;max-height:0;overflow:hidden">${escape(title)} — ${escape(brand)}</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
    <tr>
      <td align="center">
        <table role="presentation" width="600" cellspacing="0" cellpadding="0" style="width:100%;max-width:600px;background:#ffffff;border-radius:24px;overflow:hidden;box-shadow:0 20px 25px -5px rgba(0,0,0,0.1),0 8px 10px -6px rgba(0,0,0,0.1)">
          <tr><td style="height:8px;background:linear-gradient(90deg, ${color}, #0d9488)"></td></tr>
          <tr>
            <td style="padding:36px 32px 24px;text-align:center">
              ${logoHtml}
              <div style="font-size:13px;font-weight:700;letter-spacing:2.5px;text-transform:uppercase;color:${color}">${escape(brand)}</div>
              <h1 style="font-size:26px;font-weight:800;color:#0f172a;line-height:1.25;margin:16px 0 0">${escape(title)}</h1>
            </td>
          </tr>
          <tr>
            <td style="padding:8px 32px 32px;font-size:15px;line-height:1.7;color:#334155">
              ${p.name ? `<p style="margin-top:0">Bonjour <strong>${escape(p.name)}</strong>,</p>` : ''}
              <p style="white-space:pre-line">${escape(intro)}</p>

              ${details.length > 0 ? `
              <div style="margin:24px 0;background:#f8fafc;border:1px solid #e2e8f0;border-radius:16px;overflow:hidden">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                  ${details.map(([label, value], idx) => `
                  <tr style="${idx < details.length - 1 ? 'border-bottom:1px solid #e2e8f0;' : ''}">
                    <td style="padding:12px 18px;font-size:13px;color:#64748b;font-weight:500">${escape(label)}</td>
                    <td style="padding:12px 18px;text-align:right;font-size:14px;font-weight:700;color:#0f172a">${escape(value)}</td>
                  </tr>`).join('')}
                </table>
              </div>` : ''}

              ${note ? `<div style="background:#f0fdf4;border-left:4px solid ${color};padding:14px 18px;border-radius:8px;font-size:13px;color:#166534;margin:24px 0">${escape(note)}</div>` : ''}

              <p style="margin-bottom:0;font-size:14px;color:#475569">
                Cordialement,<br>
                <strong style="color:#0f172a">${escape(brand)}</strong>
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding:24px 32px;background:#f8fafc;border-top:1px solid #e2e8f0;text-align:center;font-size:12px;line-height:1.6;color:#64748b">
              ${escape(contact)}<br>
              Système de gestion GymDesk · Notification certifiée
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

  return {
    subject: `${title} — ${line(brand)}`,
    html,
    text: [
      title,
      p.name ? `Bonjour ${p.name},` : '',
      intro,
      ...details.map(([label, value]) => `${label} : ${value}`),
      note,
      contact,
    ].filter(Boolean).join('\n\n'),
  };
}
