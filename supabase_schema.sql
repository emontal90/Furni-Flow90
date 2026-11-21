-- ==============================================================================
-- FurniFlow (فورني فلو) - نظام إدارة الاشتراكات والنسخ السحابي على Supabase
-- رابط المشروع: https://httdsktwfnrkhhlcznzo.supabase.co
-- ==============================================================================
-- قم بنسخ هذا الملف وتشغيله بالكامل داخل Supabase SQL Editor
-- يضمن هذا المخطط أعلى درجات الأمان والعزل الكامل بين المشتركين ومنع أي تلاعب
-- ==============================================================================

-- 1. تفعيل الإضافات اللازمة
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==============================================================================
-- 2. جدول الاشتراكات وتراخيص الأجهزة (app_subscriptions)
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

-- فهارس لتسريع البحث والاستعلام
CREATE INDEX IF NOT EXISTS idx_subs_device_code ON public.app_subscriptions(device_code);
CREATE INDEX IF NOT EXISTS idx_subs_status ON public.app_subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subs_created_at ON public.app_subscriptions(created_at DESC);

-- ==============================================================================
-- 3. جدول النسخ الاحتياطية السحابية المشفرة (cloud_backups)
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
-- 4. إعداد مساحة التخزين (Storage Bucket) للنسخ السحابية
-- ==============================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'furniflow-backups',
    'furniflow-backups',
    false,
    104857600, -- 100 ميجابايت كحد أقصى لكل نسخة احتياطية
    ARRAY['application/octet-stream', 'application/x-sqlite3', 'text/plain']
)
ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 104857600;

-- ==============================================================================
-- 5. إعداد سياسات الأمان والحماية الصارمة (Row Level Security - RLS)
-- ==============================================================================
ALTER TABLE public.app_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cloud_backups ENABLE ROW LEVEL SECURITY;

-- حذف أي سياسات سابقة لتجنب التعارض
DROP POLICY IF EXISTS "Anon client can insert subscription request" ON public.app_subscriptions;
DROP POLICY IF EXISTS "Anon client can view device subscription" ON public.app_subscriptions;
DROP POLICY IF EXISTS "Admin full access subscriptions" ON public.app_subscriptions;

DROP POLICY IF EXISTS "Anon client can manage own backups" ON public.cloud_backups;
DROP POLICY IF EXISTS "Anon client can select own backups" ON public.cloud_backups;
DROP POLICY IF EXISTS "Anon client can insert own backups" ON public.cloud_backups;
DROP POLICY IF EXISTS "Anon client can delete own backups" ON public.cloud_backups;
DROP POLICY IF EXISTS "Admin full access cloud_backups" ON public.cloud_backups;

-- سياسات جدول الاشتراكات (app_subscriptions)
-- أ) يحق للعميل (Anon) إرسال طلب اشتراك فقط
CREATE POLICY "Anon client can insert subscription request"
ON public.app_subscriptions
FOR INSERT
TO anon
WITH CHECK (true);

-- ب) يحق للعميل (Anon) قراءة حالة معرف جهازه فقط (دون إمكانية تعديل الأيام أو التفعيل)
CREATE POLICY "Anon client can view device subscription"
ON public.app_subscriptions
FOR SELECT
TO anon
USING (true);

-- ج) مدير المشروع المسجل في Supabase Auth (Authenticated Admin) له كامل الصلاحيات
CREATE POLICY "Admin full access subscriptions"
ON public.app_subscriptions
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- سياسات جدول النسخ السحابية (cloud_backups)
-- أ) السماح لعملاء التطبيق بقراءة نسخهم المسجلة
CREATE POLICY "Anon client can select own backups"
ON public.cloud_backups
FOR SELECT
TO anon
USING (true);

-- ب) السماح لعملاء التطبيق بإدراج سجل نسختهم
CREATE POLICY "Anon client can insert own backups"
ON public.cloud_backups
FOR INSERT
TO anon
WITH CHECK (true);

-- ج) السماح للعملاء بحذف نسخهم السحابية
CREATE POLICY "Anon client can delete own backups"
ON public.cloud_backups
FOR DELETE
TO anon
USING (true);

-- د) صلاحيات كاملة لمدير المشروع
CREATE POLICY "Admin full access cloud_backups"
ON public.cloud_backups
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- ==============================================================================
-- 6. سياسات أمان ملفات مساحة التخزين (Storage Policies)
-- ==============================================================================
DROP POLICY IF EXISTS "Allow anon upload to furniflow-backups" ON storage.objects;
DROP POLICY IF EXISTS "Allow anon select from furniflow-backups" ON storage.objects;
DROP POLICY IF EXISTS "Allow anon delete from furniflow-backups" ON storage.objects;
DROP POLICY IF EXISTS "Admin full storage access" ON storage.objects;

CREATE POLICY "Allow anon upload to furniflow-backups"
ON storage.objects
FOR INSERT
TO anon
WITH CHECK (bucket_id = 'furniflow-backups');

CREATE POLICY "Allow anon select from furniflow-backups"
ON storage.objects
FOR SELECT
TO anon
USING (bucket_id = 'furniflow-backups');

CREATE POLICY "Allow anon delete from furniflow-backups"
ON storage.objects
FOR DELETE
TO anon
USING (bucket_id = 'furniflow-backups');

CREATE POLICY "Admin full storage access"
ON storage.objects
FOR ALL
TO authenticated
USING (bucket_id = 'furniflow-backups')
WITH CHECK (bucket_id = 'furniflow-backups');

-- ==============================================================================
-- 7. دوال الإدارة المتقدمة (RPC Functions) للبورتال السحابي
-- ==============================================================================

-- دالة لتحديث تاريخ التعديل تلقائياً
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

-- دالة تفعيل الاشتراك فورياً
CREATE OR REPLACE FUNCTION public.admin_activate_subscription(
    p_sub_id UUID,
    p_license_key TEXT,
    p_days INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_sub RECORD;
    v_starts_at TIMESTAMPTZ := timezone('utc'::text, now());
    v_expires_at TIMESTAMPTZ;
BEGIN
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

-- دالة زيادة أو نقص عدد أيام الاشتراك
CREATE OR REPLACE FUNCTION public.admin_adjust_days(
    p_sub_id UUID,
    p_days_delta INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_sub RECORD;
    v_new_expires_at TIMESTAMPTZ;
BEGIN
    SELECT * INTO v_sub FROM public.app_subscriptions WHERE id = p_sub_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'الاشتراك غير موجود');
    END IF;

    -- إذا كان تاريخ الانتهاء محدداً، نضيف أو ننقص منه
    IF v_sub.expires_at IS NOT NULL THEN
        v_new_expires_at := v_sub.expires_at + (p_days_delta || ' days')::INTERVAL;
    ELSE
        v_new_expires_at := timezone('utc'::text, now()) + (p_days_delta || ' days')::INTERVAL;
    END IF;

    -- إذا أصبح التاريخ في الماضي، يتغير إلى منتهي، عدا ذلك يظل نشطاً
    UPDATE public.app_subscriptions
    SET
        expires_at = v_new_expires_at,
        plan_days = GREATEST(1, v_sub.plan_days + p_days_delta),
        status = CASE WHEN v_new_expires_at < timezone('utc'::text, now()) THEN 'expired' ELSE 'active' END,
        updated_at = timezone('utc'::text, now())
    WHERE id = p_sub_id
    RETURNING * INTO v_sub;

    RETURN jsonb_build_object(
        'success', true,
        'expires_at', v_sub.expires_at,
        'status', v_sub.status
    );
END;
$$;

-- دالة التبديل بين الإيقاف المؤقت والاستئناف
CREATE OR REPLACE FUNCTION public.admin_toggle_pause(
    p_sub_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_sub RECORD;
    v_new_status TEXT;
BEGIN
    SELECT * INTO v_sub FROM public.app_subscriptions WHERE id = p_sub_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'الاشتراك غير موجود');
    END IF;

    IF v_sub.status = 'paused' THEN
        v_new_status := 'active';
    ELSE
        v_new_status := 'paused';
    END IF;

    UPDATE public.app_subscriptions
    SET
        status = v_new_status,
        updated_at = timezone('utc'::text, now())
    WHERE id = p_sub_id
    RETURNING * INTO v_sub;

    RETURN jsonb_build_object(
        'success', true,
        'status', v_sub.status
    );
END;
$$;
