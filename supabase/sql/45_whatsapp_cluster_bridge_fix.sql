-- 45_whatsapp_cluster_bridge_fix.sql
-- Fè platform_whatsapp_config_get kalkile estati an sou tout liy aktif nan cluster a
-- Si omwen 1 liy pare (READY), tout sistèm nan (Web, Mobil, Caisse, Renouvèlman) rekonèt ke WhatsApp pare!

CREATE OR REPLACE FUNCTION public.platform_whatsapp_config_get()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  c public.platform_whatsapp_config;
  v_is_online boolean := false;
  v_cluster_status text := 'OFFLINE';
  v_active_phone text := null;
  v_active_qr text := null;
  v_ready_count integer := 0;
  v_scan_qr_count integer := 0;
BEGIN
  SELECT * INTO c FROM public.platform_whatsapp_config WHERE id = true LIMIT 1;

  -- 1. Tcheke estati atravè tout kont nan cluster a
  SELECT 
    coalesce(COUNT(*) FILTER (WHERE service_status = 'READY'), 0),
    coalesce(COUNT(*) FILTER (WHERE service_status = 'SCAN_QR'), 0),
    coalesce(BOOL_OR(last_heartbeat > (clock_timestamp() - interval '45 seconds')), false),
    MAX(phone_number) FILTER (WHERE service_status = 'READY'),
    MAX(qr_code) FILTER (WHERE service_status = 'SCAN_QR')
  INTO
    v_ready_count,
    v_scan_qr_count,
    v_is_online,
    v_active_phone,
    v_active_qr
  FROM public.platform_whatsapp_accounts
  WHERE is_enabled = true;

  IF v_is_online THEN
    IF v_ready_count > 0 THEN
      v_cluster_status := 'READY';
    ELSIF v_scan_qr_count > 0 THEN
      v_cluster_status := 'SCAN_QR';
    ELSE
      v_cluster_status := coalesce(c.service_status, 'DISCONNECTED');
    END IF;
  ELSE
    v_cluster_status := 'OFFLINE';
  END IF;

  RETURN jsonb_build_object(
    'gateway_url', coalesce(c.gateway_url, 'http://127.0.0.1:47812'),
    'valid_number', coalesce(v_active_phone, c.valid_number, ''),
    'default_country_code', coalesce(c.default_country_code, '509'),
    'auto_send_welcome', coalesce(c.auto_send_welcome, true),
    'auto_send_receipts', coalesce(c.auto_send_receipts, true),
    'auto_send_reminders', coalesce(c.auto_send_reminders, true),
    'reminder_days_before', coalesce(c.reminder_days_before, 7),
    'service_status', v_cluster_status,
    'connected_phone', v_active_phone,
    'push_name', c.push_name,
    'qr_code', v_active_qr,
    'queue_length', (SELECT COUNT(*) FROM public.whatsapp_messages_outbox WHERE status = 'pending'),
    'last_error', c.last_error,
    'is_online', v_is_online,
    'updated_at', clock_timestamp()
  );
END $$;

REVOKE ALL ON FUNCTION public.platform_whatsapp_config_get() FROM public;
GRANT EXECUTE ON FUNCTION public.platform_whatsapp_config_get() TO authenticated, anon;
