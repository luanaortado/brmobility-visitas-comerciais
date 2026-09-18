import { createClient } from 'npm:@supabase/supabase-js@2'
import { JWT } from 'npm:google-auth-library@9'

const cors={'Access-Control-Allow-Origin':Deno.env.get('APP_ORIGIN')??'','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
const columns:Record<string,string>={permanent_id:'AB',relationship:'AC',financial_status:'AD',training:'AE',current_account_manager:'AF',last_fleet_change:'AG',primary_contact_name:'X',primary_contact_role:'Y',primary_contact_phone:'Z',primary_contact_email:'AA'}

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
    const auth=new JWT({email:Deno.env.get('GOOGLE_SERVICE_ACCOUNT_EMAIL'),key:Deno.env.get('GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY')?.replaceAll('\\n','\n'),scopes:['https://www.googleapis.com/auth/spreadsheets']})
    const token=await auth.getAccessToken();const sheetId=Deno.env.get('GOOGLE_SHEET_ID')!
    const fields=['permanent_id','primary_contact_name','primary_contact_role','primary_contact_phone','primary_contact_email','relationship','financial_status','training','current_account_manager','last_fleet_change']
    for(const field of fields){
      const range=encodeURIComponent(`'${client.source_sheet_name}'!${columns[field]}${client.source_row}`)
      const response=await fetch(`https://sheets.googleapis.com/v4/spreadsheets/${sheetId}/values/${range}?valueInputOption=USER_ENTERED`,{method:'PUT',headers:{Authorization:`Bearer ${token.token}`,'Content-Type':'application/json'},body:JSON.stringify({values:[[client[field]??'']]})})
      if(!response.ok)throw new Error(`Google Sheets recusou ${field} (${response.status}).`)
    }
    const now=new Date().toISOString()
    await admin.from('clients').update({sheet_sync_status:'synced',sheet_synced_at:now,updated_at:now}).eq('id',clientId)
    return Response.json({ok:true},{headers:cors})
  }catch(error){return Response.json({ok:false,error:error instanceof Error?error.message:'Erro inesperado.'},{status:400,headers:cors})}
})
