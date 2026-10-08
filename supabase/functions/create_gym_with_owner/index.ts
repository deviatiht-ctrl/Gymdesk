import { createClient } from 'jsr:@supabase/supabase-js@2';

interface GymPayload {
  name: string;
  code: string;
  accent_color: string;
  currency: string;
  timezone: string;
  address?: string;
  phone?: string;
  email?: string;
  logo_url?: string;
}

interface RequestBody {
  owner_name: string;
  owner_email: string;
  owner_phone: string;
  owner_password?: string;
  gym: GymPayload;
  offer_id: string; // 'per_member' | 'tiered' | 'unlimited_annual'
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('Origin') ?? '*';
  const corsHeaders = {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Content-Type': 'application/json',
  };

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: { persistSession: false },
    });

    const body: RequestBody = await req.json();
    const { owner_name, owner_email, owner_phone, owner_password, gym, offer_id } = body;

    if (!owner_name || !owner_email || !owner_phone || !gym?.name || !gym?.code) {
      return new Response(JSON.stringify({ error: 'missing_fields' }), { status: 400, headers: corsHeaders });
    }

    const cleanEmail = owner_email.trim().toLowerCase();
    const cleanPhone = owner_phone.replace(/\s+/g, '');
    const cleanCode = gym.code.trim().toUpperCase();

    // 1. Anti-abuse : vérification email et téléphone unique
    const { data: existingStaff } = await supabase
      .from('staff')
      .select('id, user_id, phone, role')
      .or(`phone.eq.${cleanPhone}`);

    if (existingStaff && existingStaff.length > 0) {
      return new Response(JSON.stringify({ error: 'phone_already_used_for_trial' }), { status: 409, headers: corsHeaders });
    }

    // Vérifier l'unicité du code de salle
    const { data: existingGym } = await supabase
      .from('gyms')
      .select('id')
      .eq('code', cleanCode)
      .maybeSingle();

    if (existingGym) {
      return new Response(JSON.stringify({ error: 'duplicate_code' }), { status: 409, headers: corsHeaders });
    }

    // 2. Création ou récupération de l'utilisateur Auth
    let userId: string;
    const { data: existingUsers } = await supabase.auth.admin.listUsers();
    const foundUser = existingUsers?.users?.find(u => u.email?.toLowerCase() === cleanEmail);

    if (foundUser) {
      // Si l'utilisateur existe déjà, vérifier s'il a déjà une salle
      const { data: userStaff } = await supabase
        .from('staff')
        .select('id')
        .eq('user_id', foundUser.id)
        .eq('role', 'owner')
        .maybeSingle();

      if (userStaff) {
        return new Response(JSON.stringify({ error: 'owner_already_has_gym' }), { status: 409, headers: corsHeaders });
      }
      userId = foundUser.id;
    } else {
      if (!owner_password || owner_password.length < 8) {
        return new Response(JSON.stringify({ error: 'password_too_short' }), { status: 400, headers: corsHeaders });
      }
      const { data: newUser, error: createAuthError } = await supabase.auth.admin.createUser({
        email: cleanEmail,
        password: owner_password,
        email_confirm: true,
        user_metadata: { full_name: owner_name, phone: cleanPhone },
      });
      if (createAuthError || !newUser?.user) {
        return new Response(JSON.stringify({ error: createAuthError?.message ?? 'auth_creation_failed' }), { status: 500, headers: corsHeaders });
      }
      userId = newUser.user.id;
    }

    // 3. Dates d'essai serveur : 7 jours automatiques
    const now = new Date();
    const trialEndsAt = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
    const gymId = crypto.randomUUID();

    // 4. Création de la salle (status = 'trial')
    const { data: newGym, error: gymError } = await supabase
      .from('gyms')
      .insert({
        id: gymId,
        code: cleanCode,
        name: gym.name.trim(),
        accent_color: gym.accent_color || '#1F6F4A',
        timezone: gym.timezone || 'America/Port-au-Prince',
        currency: gym.currency || 'HTG',
        address: gym.address || null,
        phone: gym.phone || cleanPhone,
        email: gym.email || cleanEmail,
        logo_url: gym.logo_url || null,
        status: 'trial',
        trial_started_at: now.toISOString(),
        trial_ends_at: trialEndsAt.toISOString(),
        onboarding_done: false,
        source: 'self_signup',
        settings: {
          offline_lease_hours: 24,
          grace_days: 0,
          allow_access_pending: false,
          scan_sound: true,
          scan_vibrate: true,
          entry_duplicate_seconds: 3,
        },
      })
      .select()
      .single();

    if (gymError) {
      return new Response(JSON.stringify({ error: gymError.message }), { status: 500, headers: corsHeaders });
    }

    // 5. Création du compte staff owner
    const staffId = crypto.randomUUID();
    const { error: staffError } = await supabase
      .from('staff')
      .insert({
        id: staffId,
        user_id: userId,
        gym_id: gymId,
        role: 'owner',
        full_name: owner_name.trim(),
        phone: cleanPhone,
        active: true,
      });

    if (staffError) {
      return new Response(JSON.stringify({ error: staffError.message }), { status: 500, headers: corsHeaders });
    }

    // 6. Récupérer le snapshot de l'offre
    const { data: offer } = await supabase
      .from('platform_offers')
      .select('*')
      .eq('id', offer_id || 'per_member')
      .maybeSingle();

    // 7. Création du contrat d'essai
    await supabase
      .from('gym_contracts')
      .insert({
        gym_id: gymId,
        offer_id: offer_id || 'per_member',
        status: 'trial',
        price_snapshot: offer ? { name: offer.name, price: offer.price, currency: offer.currency, config: offer.config } : {},
        starts_at: now.toISOString(),
        expires_at: trialEndsAt.toISOString(),
      });

    // 8. Plans de membres par défaut
    const defaultPlans = [
      { name: '1 Mois', duration_days: 30, price: gym.currency === 'USD' ? 25 : 2500, sort_order: 1 },
      { name: '3 Mois', duration_days: 90, price: gym.currency === 'USD' ? 65 : 6500, sort_order: 2 },
      { name: '6 Mois', duration_days: 180, price: gym.currency === 'USD' ? 120 : 12000, sort_order: 3 },
      { name: '1 An', duration_days: 365, price: gym.currency === 'USD' ? 220 : 22000, sort_order: 4 },
      { name: 'Séance Unique', duration_days: 1, price: gym.currency === 'USD' ? 5 : 500, sort_order: 5 },
    ];

    for (const p of defaultPlans) {
      await supabase.from('plans').insert({
        gym_id: gymId,
        name: p.name,
        duration_days: p.duration_days,
        price: p.price,
        currency: gym.currency || 'HTG',
        active: true,
        sort_order: p.sort_order,
      });
    }

    // 9. Modèle de badge par défaut V2 (CR80 anonyme)
    await supabase.from('badge_templates').insert({
      gym_id: gymId,
      name: 'Badge Standard CR80 V2',
      is_default: true,
      layout: {
        orientation: 'landscape',
        accent_color: gym.accent_color || '#1F6F4A',
        show_logo: true,
        show_gym_name: true,
        show_phone: true,
        show_qr: true,
        qr_size_mm: 34,
        show_badge_number: true,
      },
    });

    // 10. Lot d'essai de 10 badges
    const batchId = crypto.randomUUID();
    await supabase.from('badge_batches').insert({
      id: batchId,
      gym_id: gymId,
      label: 'Lot d\'essai (10 badges)',
      range_from: 1,
      range_to: 10,
      quantity: 10,
      source: 'trial',
      generated_by: staffId,
    });

    const trialBadges = [];
    for (let i = 1; i <= 10; i++) {
      const tokenBytes = new Uint8Array(20);
      crypto.getRandomValues(tokenBytes);
      const token = Array.from(tokenBytes, b => b.toString(16).padStart(2, '0')).join('');
      trialBadges.push({
        id: crypto.randomUUID(),
        gym_id: gymId,
        batch_id: batchId,
        badge_number: i,
        qr_token: token,
        status: 'unassigned',
      });
    }
    await supabase.from('badges').insert(trialBadges);

    return new Response(JSON.stringify({
      success: true,
      gym: newGym,
      staff_id: staffId,
      user_id: userId,
      trial_ends_at: trialEndsAt.toISOString(),
    }), { headers: corsHeaders });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || 'internal_server_error' }), { status: 500, headers: corsHeaders });
  }
});
