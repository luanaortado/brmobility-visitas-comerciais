import { createClient } from 'npm:@supabase/supabase-js@2'

const cors={'Access-Control-Allow-Origin':Deno.env.get('APP_ORIGIN')??'','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}

Deno.serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors})
  try{
    const authorization=req.headers.get('Authorization')
    if(!authorization)throw new Error('Sessão obrigatória.')
    const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:authorization}}})
    const {data:{user}}=await db.auth.getUser();if(!user)throw new Error('Sessão inválida.')
    const {clientId}=await req.json()
    const {data:visible}=await db.rpc('get_visible_clients');if(!visible?.some((c:Record<string,unknown>)=>c.id===clientId))throw new Error('Cliente não encontrado ou sem permissão.')
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}})
    const {data:client,error}=await admin.from('clients').select('*').eq('id',clientId).single();if(error||!client)throw new Error('Cliente não encontrado.')
    const response=await fetch(Deno.env.get('APPS_SCRIPT_URL')!,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({
      secret:Deno.env.get('SHEET_SYNC_SECRET'),action:'syncClient',sheetName:Deno.env.get('GOOGLE_SHEET_TAB')??'3 Perfil do Cliente',row:client.source_row,
      permanentId:client.permanent_id,name:client.primary_contact_name,role:client.primary_contact_role,phone:client.primary_contact_phone,
      email:client.primary_contact_email,relationship:client.relationship,financial:client.financial_status,training:client.training,
      manager:client.current_account_manager,fleet:client.last_fleet_change
    })})
    const result=await response.json();if(!response.ok||!result.ok)throw new Error(result.error??`Google Sheets recusou a sincronização (${response.status}).`)
    const now=new Date().toISOString()
    await admin.from('clients').update({sheet_sync_status:'synced',sheet_synced_at:now,updated_at:now}).eq('id',clientId)
    return Response.json({ok:true},{headers:cors})
  }catch(error){return Response.json({ok:false,error:error instanceof Error?error.message:'Erro inesperado.'},{status:400,headers:cors})}
})
