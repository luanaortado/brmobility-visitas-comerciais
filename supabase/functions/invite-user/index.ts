import { createClient } from 'npm:@supabase/supabase-js@2'

const cors = { 'Access-Control-Allow-Origin': Deno.env.get('APP_ORIGIN') ?? '', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const authorization = req.headers.get('Authorization')
    const userDb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authorization ?? '' } } })
    const { data: { user } } = await userDb.auth.getUser()
    if (!user) throw new Error('Sessão obrigatória.')
    const { data: profile } = await userDb.from('profiles').select('role').eq('id', user.id).single()
    if (profile?.role !== 'admin') throw new Error('Apenas administradores podem convidar usuários.')
    const { email, fullName, role = 'representative' } = await req.json()
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } })
    const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { data: { full_name: fullName, role }, redirectTo: Deno.env.get('APP_ORIGIN') })
    if (error) throw error
    return Response.json({ ok: true, userId: data.user.id }, { headers: cors })
  } catch (error) {
    return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Erro inesperado.' }, { status: 400, headers: cors })
  }
})
