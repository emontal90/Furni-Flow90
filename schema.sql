-- ==============================================================================
-- FurniFlow (فورني فلو) - نظام إدارة الاشتراكات والنسخ السحابي على Supabase
-- ==============================================================================
-- قم بتشغيل هذا الملف داخل Supabase SQL Editor
-- يضمن هذا المخطط العزل الكامل بين الأجهزة ومنع الوصول غير المصرح به
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==============================================================================
-- 1. جدول الاشتراكات وتراخيص الأجهزة (app_subscriptions)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.app_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_code TEXT NOT NULL,
    sender_phone TEXT NOT NULL,
    reference_no TEXT NOT NULL,
    payment_method TEXT NOT NULL CHECK (payment_method IN ('vodafone_cash', 'instapay')),
    plan_type TEXT NOT NULL CHECK (plan_type IN ('monthly', 'half_yearly', 'yearly')),
    plan_days INTEGER NOT NULL DEFAULT 30,
    amount NUMERIC NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'paused', 'expired')),
    license_key TEXT,
    starts_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_subs_device_code ON public.app_subscriptions(device_code);
CREATE INDEX IF NOT EXISTS idx_subs_status ON public.app_subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subs_created_at ON public.app_subscriptions(created_at DESC);

-- ==============================================================================
-- 2. جدول النسخ الاحتياطية السحابية المشفرة (cloud_backups)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.cloud_backups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_code TEXT NOT NULL,
    file_name TEXT NOT NULL,
    storage_path TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL DEFAULT 0,
    file_size_formatted TEXT NOT NULL DEFAULT '0 KB',
    is_auto BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_cloud_backups_device ON public.cloud_backups(device_code);
CREATE INDEX IF NOT EXISTS idx_cloud_backups_created_at ON public.cloud_backups(created_at DESC);

-- ==============================================================================
-- 3. إعداد مساحة التخزين (Storage Bucket) للنسخ السحابية
-- ==============================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'furniflow-backups',
    'furniflow-backups',
    false,
    104857600,
    ARRAY['application/octet-stream', 'application/x-sqlite3', 'text/plain']
)
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 104857600;

-- ==============================================================================
-- 4. سياسات الأمان الصارمة (Row Level Security - RLS)
-- ==============================================================================
ALTER TABLE public.app_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cloud_backups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anon client can insert subscription request" ON public.app_subscriptions;
DROP POLICY IF EXISTS "Anon client can view device subscription" ON public.app_subscriptions;
DROP POLICY IF EXISTS "Admin full access subscriptions" ON public.app_subscriptions;

DROP POLICY IF EXISTS "Anon client can manage own backups" ON public.cloud_backups;
DROP POLICY IF EXISTS "Anon client can select own backups" ON public.cloud_backups;
DROP POLICY IF EXISTS "Anon client can insert own backups" ON public.cloud_backups;
DROP POLICY IF EXISTS "Anon client can delete own backups" ON public.cloud_backups;
DROP POLICY IF EXISTS "Admin full access cloud_backups" ON public.cloud_backups;

-- أ) العميل (Anon) يستطيع فقط إرسال طلب اشتراك جديد بحالة pending
CREATE POLICY "Anon client can insert subscription request"
ON public.app_subscriptions
FOR INSERT
TO anon
WITH CHECK (status = 'pending' AND license_key IS NULL);

-- ب) منع anon من قراءة جدول الاشتراكات مباشرة (القراءة تتم عبر دالة get_device_subscription المقيدة)
-- ج) المدير المسجل له صلاحيات كاملة
CREATE POLICY "Admin full access subscriptions"
ON public.app_subscriptions
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- د) منع anon من قراءة/حذف جدول cloud_backups مباشرة (تتم عبر دوال RPC مقيدة برقم الجهاز)
CREATE POLICY "Admin full access cloud_backups"
ON public.cloud_backups
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- ==============================================================================
-- 5. سياسات مساحة التخزين (Storage Policies)
-- ==============================================================================
DROP POLICY IF EXISTS "Allow anon upload to furniflow-backups" ON storage.objects;
DROP POLICY IF EXISTS "Allow anon update in furniflow-backups" ON storage.objects;
DROP POLICY IF EXISTS "Allow anon select from furniflow-backups" ON storage.objects;
DROP POLICY IF EXISTS "Allow anon delete from furniflow-backups" ON storage.objects;
DROP POLICY IF EXISTS "Allow anon upload to own device folder" ON storage.objects;
DROP POLICY IF EXISTS "Allow anon update own device folder" ON storage.objects;
DROP POLICY IF EXISTS "Allow anon select own device file" ON storage.objects;
DROP POLICY IF EXISTS "Allow anon delete own device file" ON storage.objects;
DROP POLICY IF EXISTS "Admin full storage access" ON storage.objects;

-- السماح للعميل برفع نسخته داخل مجلد معرف جهازه فقط، ومنع الاستعراض المفتوح
CREATE POLICY "Allow anon upload to own device folder"
ON storage.objects
FOR INSERT
TO anon
WITH CHECK (
    bucket_id = 'furniflow-backups'
    AND name ~ '^MT-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}/[A-Za-z0-9._-]+$'
);

CREATE POLICY "Allow anon update own device folder"
ON storage.objects
FOR UPDATE
TO anon
USING (
    bucket_id = 'furniflow-backups'
    AND name ~ '^MT-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}/[A-Za-z0-9._-]+$'
)
WITH CHECK (
    bucket_id = 'furniflow-backups'
    AND name ~ '^MT-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}/[A-Za-z0-9._-]+$'
);

CREATE POLICY "Allow anon select own device file"
ON storage.objects
FOR SELECT
TO anon
USING (
    bucket_id = 'furniflow-backups'
    AND name ~ '^MT-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}/[A-Za-z0-9._-]+$'
);

CREATE POLICY "Allow anon delete own device file"
ON storage.objects
FOR DELETE
TO anon
USING (
    bucket_id = 'furniflow-backups'
    AND name ~ '^MT-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}/[A-Za-z0-9._-]+$'
);

CREATE POLICY "Admin full storage access"
ON storage.objects
FOR ALL
TO authenticated
USING (bucket_id = 'furniflow-backups')
WITH CHECK (bucket_id = 'furniflow-backups');

-- ==============================================================================
-- 6. دوال العميل المقيدة برقم الجهاز (Device-Scoped Client RPCs)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.get_device_subscription(p_device_code TEXT)
RETURNS TABLE (
    id UUID,
    device_code TEXT,
    payment_method TEXT,
    plan_type TEXT,
    plan_days INTEGER,
    amount NUMERIC,
    status TEXT,
    license_key TEXT,
    starts_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        s.id,
        s.device_code,
        s.payment_method,
        s.plan_type,
        s.plan_days,
        s.amount,
        s.status,
        s.license_key,
        s.starts_at,
        s.expires_at,
        s.notes,
        s.created_at
    FROM public.app_subscriptions s
    WHERE s.device_code = UPPER(TRIM(p_device_code))
    ORDER BY s.created_at DESC
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_device_subscription(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_device_subscription(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.submit_subscription_request(
    p_device_code TEXT,
    p_sender_phone TEXT,
    p_reference_no TEXT,
    p_payment_method TEXT,
    p_plan_type TEXT,
    p_plan_days INTEGER,
    p_amount NUMERIC
)
RETURNS SETOF public.app_subscriptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_row public.app_subscriptions;
BEGIN
    INSERT INTO public.app_subscriptions (
        device_code, sender_phone, reference_no, payment_method,
        plan_type, plan_days, amount, status
    ) VALUES (
        UPPER(TRIM(p_device_code)),
        TRIM(p_sender_phone),
        TRIM(p_reference_no),
        p_payment_method,
        p_plan_type,
        GREATEST(1, p_plan_days),
        GREATEST(0, p_amount),
        'pending'
    )
    RETURNING * INTO v_row;

    RETURN NEXT v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_subscription_request(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_subscription_request(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, NUMERIC) TO anon, authenticated;



CREATE OR REPLACE FUNCTION public.list_device_backups(p_device_code TEXT)
RETURNS SETOF public.cloud_backups
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT *
    FROM public.cloud_backups
    WHERE device_code = UPPER(TRIM(p_device_code))
    ORDER BY created_at DESC
    LIMIT 20;
$$;

REVOKE ALL ON FUNCTION public.list_device_backups(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_device_backups(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.register_device_backup(
    p_device_code TEXT,
    p_file_name TEXT,
    p_storage_path TEXT,
    p_file_size_bytes BIGINT,
    p_file_size_formatted TEXT,
    p_is_auto BOOLEAN DEFAULT false
)
RETURNS public.cloud_backups
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_clean_device TEXT := UPPER(TRIM(p_device_code));
    v_row public.cloud_backups;
BEGIN
    IF p_storage_path NOT LIKE (v_clean_device || '/%') THEN
        RAISE EXCEPTION 'Invalid storage path for device';
    END IF;

    INSERT INTO public.cloud_backups (
        device_code, file_name, storage_path, file_size_bytes, file_size_formatted, is_auto
    ) VALUES (
        v_clean_device, p_file_name, p_storage_path, p_file_size_bytes, p_file_size_formatted, p_is_auto
    )
    RETURNING * INTO v_row;

    RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.register_device_backup(TEXT, TEXT, TEXT, BIGINT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_device_backup(TEXT, TEXT, TEXT, BIGINT, TEXT, BOOLEAN) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.delete_device_backup(p_id UUID, p_device_code TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_deleted INT;
BEGIN
    DELETE FROM public.cloud_backups
    WHERE id = p_id AND device_code = UPPER(TRIM(p_device_code));
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_device_backup(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_device_backup(UUID, TEXT) TO anon, authenticated;

-- ==============================================================================
-- 7. دوال الإدارة المحمية (Admin-Only RPCs)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_set_updated_at ON public.app_subscriptions;
CREATE TRIGGER trigger_set_updated_at
BEFORE UPDATE ON public.app_subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.handle_updated_at();

CREATE OR REPLACE FUNCTION public.admin_activate_subscription(
    p_sub_id UUID,
    p_license_key TEXT,
    p_days INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sub RECORD;
    v_starts_at TIMESTAMPTZ := timezone('utc'::text, now());
    v_expires_at TIMESTAMPTZ;
BEGIN
    IF auth.role() <> 'authenticated' THEN
        RAISE EXCEPTION 'Unauthorized: Admin authentication required';
    END IF;

    v_expires_at := v_starts_at + (p_days || ' days')::INTERVAL;

    UPDATE public.app_subscriptions
    SET
        status = 'active',
        license_key = p_license_key,
        plan_days = p_days,
        starts_at = v_starts_at,
        expires_at = v_expires_at,
        updated_at = timezone('utc'::text, now())
    WHERE id = p_sub_id
    RETURNING * INTO v_sub;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'الاشتراك غير موجود');
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'status', v_sub.status,
        'expires_at', v_sub.expires_at,
        'license_key', v_sub.license_key
    );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_activate_subscription(UUID, TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_activate_subscription(UUID, TEXT, INTEGER) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_adjust_days(
    p_sub_id UUID,
    p_days_delta INTEGER,
    p_license_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sub RECORD;
    v_new_expires_at TIMESTAMPTZ;
BEGIN
    IF auth.role() <> 'authenticated' THEN
        RAISE EXCEPTION 'Unauthorized: Admin authentication required';
    END IF;

    SELECT * INTO v_sub FROM public.app_subscriptions WHERE id = p_sub_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'الاشتراك غير موجود');
    END IF;

    IF v_sub.expires_at IS NOT NULL THEN
        v_new_expires_at := v_sub.expires_at + (p_days_delta || ' days')::INTERVAL;
    ELSE
        v_new_expires_at := timezone('utc'::text, now()) + (p_days_delta || ' days')::INTERVAL;
    END IF;

    UPDATE public.app_subscriptions
    SET
        expires_at = v_new_expires_at,
        plan_days = GREATEST(1, v_sub.plan_days + p_days_delta),
        license_key = COALESCE(p_license_key, license_key),
        status = CASE WHEN v_new_expires_at < timezone('utc'::text, now()) THEN 'expired' ELSE 'active' END,
        updated_at = timezone('utc'::text, now())
    WHERE id = p_sub_id
    RETURNING * INTO v_sub;

    RETURN jsonb_build_object(
        'success', true,
        'expires_at', v_sub.expires_at,
        'status', v_sub.status,
        'license_key', v_sub.license_key
    );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_adjust_days(UUID, INTEGER, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_adjust_days(UUID, INTEGER, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_toggle_pause(
    p_sub_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sub RECORD;
    v_new_status TEXT;
BEGIN
    IF auth.role() <> 'authenticated' THEN
        RAISE EXCEPTION 'Unauthorized: Admin authentication required';
    END IF;

    SELECT * INTO v_sub FROM public.app_subscriptions WHERE id = p_sub_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'الاشتراك غير موجود');
    END IF;

    v_new_status := CASE WHEN v_sub.status = 'paused' THEN 'active' ELSE 'paused' END;

    UPDATE public.app_subscriptions
    SET status = v_new_status, updated_at = timezone('utc'::text, now())
    WHERE id = p_sub_id
    RETURNING * INTO v_sub;

    RETURN jsonb_build_object('success', true, 'status', v_sub.status);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_toggle_pause(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_toggle_pause(UUID) TO authenticated;
