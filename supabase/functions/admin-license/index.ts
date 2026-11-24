import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

async function computeHmacHex8(secret: string, payload: string): Promise<string> {
  const enc = new TextEncoder()
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  )
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(payload))
  const hex = Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
    .toUpperCase()
  return hex.substring(0, 8)
}

function formatDateToToken(date: Date): string {
  const y = date.getUTCFullYear()
  const m = String(date.getUTCMonth() + 1).padStart(2, '0')
  const d = String(date.getUTCDate()).padStart(2, '0')
  return `${y}${m}${d}`
}

async function generateLicenseKey(
  secret: string,
  deviceCode: string,
  expiryToken: string
): Promise<string> {
  const cleanDevice = deviceCode.trim().toUpperCase()
  const cleanExpiry = expiryToken.trim().toUpperCase()
  const sig = await computeHmacHex8(secret, `${cleanDevice}|${cleanExpiry}`)
  return `MTK-${cleanExpiry}-${sig}`
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    const signingSecret = Deno.env.get('LICENSE_SIGNING_SECRET') ?? ''

    if (!signingSecret) {
      return new Response(
        JSON.stringify({ error: 'LICENSE_SIGNING_SECRET is not configured in Supabase Secrets' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify caller is an authenticated admin user
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: userData, error: userErr } = await userClient.auth.getUser()
    if (userErr || !userData?.user) {
      return new Response(JSON.stringify({ error: 'Invalid or expired admin session' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey)
    const body = await req.json()
    const action = String(body.action ?? '')
    const subId = String(body.sub_id ?? '')

    if (!subId) {
      return new Response(JSON.stringify({ error: 'sub_id is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data: sub, error: fetchErr } = await adminClient
      .from('app_subscriptions')
      .select('*')
      .eq('id', subId)
      .single()

    if (fetchErr || !sub) {
      return new Response(JSON.stringify({ error: 'Subscription not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const now = new Date()

    if (action === 'activate') {
      const days = Math.max(1, Number(body.days ?? sub.plan_days ?? 30))
      const expiryDate = new Date(now.getTime() + days * 24 * 60 * 60 * 1000)
      const expiryToken = formatDateToToken(expiryDate)
      const licenseKey = await generateLicenseKey(signingSecret, sub.device_code, expiryToken)

      const { error: updErr } = await adminClient
        .from('app_subscriptions')
        .update({
          status: 'active',
          license_key: licenseKey,
          plan_days: days,
          starts_at: now.toISOString(),
          expires_at: expiryDate.toISOString(),
          notes: 'COMMERCIAL_ACTIVATED',
          updated_at: now.toISOString(),
        })
        .eq('id', subId)

      if (updErr) throw updErr

      return new Response(
        JSON.stringify({
          success: true,
          device_code: sub.device_code,
          plan_days: days,
          license_key: licenseKey,
          expires_at: expiryDate.toISOString(),
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (action === 'adjust_days') {
      const delta = Number(body.delta ?? 0)
      let baseDate = sub.expires_at ? new Date(sub.expires_at) : new Date()
      if (delta > 0 && baseDate < now) baseDate = now

      const newExpiry = new Date(baseDate.getTime() + delta * 24 * 60 * 60 * 1000)
      const newDays = Math.max(1, Number(sub.plan_days ?? 30) + delta)
      const isExpired = newExpiry < now
      const expiryToken = formatDateToToken(newExpiry)
      const newLicenseKey = await generateLicenseKey(signingSecret, sub.device_code, expiryToken)

      const { error: updErr } = await adminClient
        .from('app_subscriptions')
        .update({
          expires_at: newExpiry.toISOString(),
          plan_days: newDays,
          license_key: newLicenseKey,
          status: isExpired ? 'expired' : 'active',
          updated_at: now.toISOString(),
        })
        .eq('id', subId)

      if (updErr) throw updErr

      return new Response(
        JSON.stringify({
          success: true,
          status: isExpired ? 'expired' : 'active',
          plan_days: newDays,
          license_key: newLicenseKey,
          expires_at: newExpiry.toISOString(),
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(JSON.stringify({ error: 'Unsupported action' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
