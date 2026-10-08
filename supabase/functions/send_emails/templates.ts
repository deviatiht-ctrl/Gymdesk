import type { EmailJob } from './handler.ts';

const escape = (value: unknown) => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
const line = (value: unknown) => String(value ?? '').replace(/[\r\n]/g, ' ').slice(0, 200);

export function renderEmail(job: EmailJob, logoUrl: string | null) {
  const p = job.payload;
  const platform = job.kind === 'gym_welcome';
  const renewal = job.kind === 'member_renewal';
  const brand = platform ? 'GymDesk' : String(p.gym_name ?? 'Votre salle');
  const title = platform ? 'Bienvenue sur GymDesk' : renewal ? 'Renouvellement confirmé' : 'Bienvenue dans votre salle';
  const intro = platform
    ? 'Merci d’avoir choisi GymDesk pour accompagner votre salle. Votre espace est prêt : gérez vos membres, vos badges et vos abonnements en un seul endroit.'
    : renewal ? 'Merci pour votre confiance renouvelée. Votre abonnement a été renouvelé. Nous sommes heureux de poursuivre cette aventure avec vous.'
    : p.imported ? 'Merci de faire partie de notre salle. Votre dossier et votre période déjà réglée ont été repris dans GymDesk, sans nouveaux frais d’inscription.'
    : 'Merci pour votre inscription et pour votre confiance. Votre badge est maintenant associé à votre dossier. Toute l’équipe vous souhaite la bienvenue.';
  const rows: [string, unknown][] = platform
    ? [['Salle', p.gym_name], ['Offre choisie', p.plan_name], ['Tarif de l’offre', p.price == null ? 'Selon votre contrat' : `${p.price} ${p.currency ?? ''}`], ['Quota de badges du forfait', p.badge_quota ?? 'Selon votre contrat'], ['Statut', p.status === 'trial' ? 'Période d’essai' : 'Compte activé'], ['Fin de période', p.end_date]]
    : [['Membre', p.name], ['Numéro de membre', p.member_number], ['Formule', p.plan_name], ['Début', p.start_date], ['Fin de période', p.end_date], ['Montant de la période', `${p.price ?? 0} ${p.currency ?? ''}`], ['Statut', p.imported ? 'Période déjà réglée avant la reprise' : p.status === 'active' ? 'Abonnement actif' : 'En attente de règlement / validation']];
  const note = platform
    ? 'Les conditions de votre offre s’appliquent après l’essai. Cet email n’est pas une confirmation de paiement.'
    : 'Gardez votre badge et votre code PIN personnels. Aucun code PIN ne vous sera demandé par email. Pour toute question, contactez la réception.';
  const color = !platform && /^#[0-9a-f]{6}$/i.test(String(p.accent_color)) ? String(p.accent_color) : '#176B52';
  let logo = '';
  if (logoUrl) {
    try {
      const url = new URL(logoUrl);
      if (url.protocol === 'https:' && !url.username && !url.password) logo = `<img src="${escape(url.href)}" alt="${escape(brand)}" width="96" style="display:block;max-width:96px;max-height:96px;object-fit:contain;margin:0 auto 18px">`;
    } catch { logo = ''; }
  }
  const details = rows.filter(([, value]) => value != null && value !== '');
  const contact = platform ? 'GymDesk — Gestion de votre salle' : [p.gym_phone, p.gym_address].filter(Boolean).join(' · ');
  const html = `<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escape(title)}</title></head>
<body style="margin:0;padding:24px 12px;background:#f2f5f4;color:#20352e;font-family:Arial,Helvetica,sans-serif">
<div style="display:none;max-height:0;overflow:hidden">${escape(title)} — ${escape(brand)}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td align="center">
<table role="presentation" width="600" cellspacing="0" cellpadding="0" style="width:100%;max-width:600px;background:#fff;border-radius:20px;overflow:hidden">
<tr><td style="height:8px;background:${color}"></td></tr>
<tr><td style="padding:32px 28px 20px;text-align:center">${logo}<div style="font-size:14px;font-weight:bold;letter-spacing:2px;color:${color}">${escape(brand)}</div><h1 style="font-size:28px;line-height:1.25;margin:20px 0 0">${escape(title)}</h1></td></tr>
<tr><td style="padding:8px 28px 28px;font-size:16px;line-height:1.7"><p>Bonjour ${escape(p.name)},</p><p>${escape(intro)}</p>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f8f6;border-radius:12px">${details.map(([label, value]) => `<tr><td style="padding:12px 16px;border-bottom:1px solid #e3ece7;font-size:13px;color:#53695f">${escape(label)}</td><td style="padding:12px 16px;border-bottom:1px solid #e3ece7;text-align:right;font-size:14px;font-weight:bold">${escape(value)}</td></tr>`).join('')}</table>
<p style="font-size:13px;color:#53695f;margin-top:24px">${escape(note)}</p><p style="font-weight:bold">À très bientôt,<br>${escape(brand)}</p></td></tr>
<tr><td style="padding:20px 28px;background:#eaf2ee;text-align:center;font-size:12px;line-height:1.6;color:#53695f">${escape(contact)}<br>Notification automatique · GymDesk</td></tr>
</table></td></tr></table></body></html>`;
  return { subject: `${title} — ${line(brand)}`, html, text: [title, `Bonjour ${p.name ?? ''},`, intro, ...details.map(([label, value]) => `${label} : ${value}`), note, contact].join('\n\n') };
}
