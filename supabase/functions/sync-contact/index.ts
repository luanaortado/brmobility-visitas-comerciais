import { createClient } from 'npm:@supabase/supabase-js@2'
import { JWT } from 'npm:google-auth-library@9'

const cors = { 'Access-Control-Allow-Origin': Deno.env.get('APP_ORIGIN') ?? '', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const authorization = req.headers.get('Authorization')
    if (!authorization) throw new Error('Sessão obrigatória.')
    const url = Deno.env.get('SUPABASE_URL')!
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!
    const db = createClient(url, anon, { global: { headers: { Authorization: authorization } } })
    const { data: { user } } = await db.auth.getUser()
    if (!user) throw new Error('Sessão inválida.')

    const { clientId, name, role, phone, email } = await req.json()
    const { data: client, error: readError } = await db.from('clients').select('id,source_row,source_sheet_name').eq('id', clientId).single()
    if (readError || !client) throw new Error('Cliente não encontrado ou sem permissão.')

    const auth = new JWT({
      email: Deno.env.get('GOOGLE_SERVICE_ACCOUNT_EMAIL'),
      key: Deno.env.get('GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY')?.replaceAll('\\n', '\n'),
      scopes: ['https://www.googleapis.com/auth/spreadsheets'],
    })
    const token = await auth.getAccessToken()
    const sheetId = Deno.env.get('GOOGLE_SHEET_ID')!
    const range = encodeURIComponent(`'${client.source_sheet_name}'!X${client.source_row}:AA${client.source_row}`)
    const sheetResponse = await fetch(`https://sheets.googleapis.com/v4/spreadsheets/${sheetId}/values/${range}?valueInputOption=USER_ENTERED`, {
      method: 'PUT', headers: { Authorization: `Bearer ${token.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ range, majorDimension: 'ROWS', values: [[name, role, phone, email]] }),
    })
    if (!sheetResponse.ok) throw new Error(`Google Sheets recusou a sincronização (${sheetResponse.status}).`)

    const { error: updateError } = await db.from('clients').update({
      primary_contact_name: name, primary_contact_role: role, primary_contact_phone: phone, primary_contact_email: email,
      sheet_sync_status: 'synced', sheet_synced_at: new Date().toISOString(), updated_at: new Date().toISOString(),
    }).eq('id', clientId)
    if (updateError) throw updateError
    return Response.json({ ok: true }, { headers: cors })
  } catch (error) {
    return Response.json({ ok: false, error: error instanceof Error ? error.message : 'Erro inesperado.' }, { status: 400, headers: cors })
  }
})
