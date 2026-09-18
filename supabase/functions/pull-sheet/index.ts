import { createClient } from 'npm:@supabase/supabase-js@2'
import { JWT } from 'npm:google-auth-library@9'

// Scheduled/webhook import. The UUID written in column AB is the only matching key.
Deno.serve(async req=>{
  try{
    if(req.headers.get('x-sync-secret')!==Deno.env.get('SHEET_SYNC_SECRET'))throw new Error('Não autorizado.')
    const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}})
    const auth=new JWT({email:Deno.env.get('GOOGLE_SERVICE_ACCOUNT_EMAIL'),key:Deno.env.get('GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY')?.replaceAll('\\n','\n'),scopes:['https://www.googleapis.com/auth/spreadsheets.readonly']})
    const token=await auth.getAccessToken();const sheetId=Deno.env.get('GOOGLE_SHEET_ID')!;const tab=Deno.env.get('GOOGLE_SHEET_TAB')??'Perfil do Cliente'
    const range=encodeURIComponent(`'${tab}'!X2:AG`)
    const response=await fetch(`https://sheets.googleapis.com/v4/spreadsheets/${sheetId}/values/${range}`,{headers:{Authorization:`Bearer ${token.token}`}})
    if(!response.ok)throw new Error(`Falha ao ler planilha (${response.status}).`)
    const {values=[]}=await response.json();let updated=0
    for(const row of values){
      const [name,role,phone,email,permanentId,relationship,financial,training,manager,fleet]=row
      if(!permanentId)continue
      const {data:current}=await db.from('clients').select('sync_updated_at').eq('permanent_id',permanentId).maybeSingle()
      const sheetUpdated=req.headers.get('x-sheet-updated-at')??new Date().toISOString()
      if(current&&new Date(current.sync_updated_at)>new Date(sheetUpdated))continue
      const {error}=await db.from('clients').update({primary_contact_name:name||null,primary_contact_role:role||null,primary_contact_phone:phone||null,primary_contact_email:email||null,relationship,financial_status:financial,training,current_account_manager:manager,last_fleet_change:fleet?`${fleet.slice(0,7)}-01`:null,sync_source:'sheet',sync_updated_at:sheetUpdated,sheet_sync_status:'synced',sheet_synced_at:new Date().toISOString()}).eq('permanent_id',permanentId)
      if(!error)updated++
    }
    return Response.json({ok:true,updated})
  }catch(error){return Response.json({ok:false,error:error instanceof Error?error.message:'Erro inesperado.'},{status:400})}
})
