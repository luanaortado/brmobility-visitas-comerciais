import { createClient } from 'npm:@supabase/supabase-js@2'
import { JWT } from 'npm:google-auth-library@9'

// One-time/idempotent rollout: publishes the database UUID to column AB.
Deno.serve(async req=>{
  try{
    if(req.headers.get('x-sync-secret')!==Deno.env.get('SHEET_SYNC_SECRET'))throw new Error('Não autorizado.')
    const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}})
    const {data:clients,error}=await db.from('clients').select('id,permanent_id,source_row,source_sheet_name').not('source_row','is',null)
    if(error)throw error
    const auth=new JWT({email:Deno.env.get('GOOGLE_SERVICE_ACCOUNT_EMAIL'),key:Deno.env.get('GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY')?.replaceAll('\\n','\n'),scopes:['https://www.googleapis.com/auth/spreadsheets']})
    const token=await auth.getAccessToken();const sheetId=Deno.env.get('GOOGLE_SHEET_ID')!;let updated=0
    for(const client of clients??[]){
      const range=encodeURIComponent(`'${client.source_sheet_name}'!AB${client.source_row}`)
      const response=await fetch(`https://sheets.googleapis.com/v4/spreadsheets/${sheetId}/values/${range}?valueInputOption=RAW`,{method:'PUT',headers:{Authorization:`Bearer ${token.token}`,'Content-Type':'application/json'},body:JSON.stringify({values:[[client.permanent_id]]})})
      if(!response.ok)throw new Error(`Falha na linha ${client.source_row} (${response.status}).`)
      updated++
    }
    return Response.json({ok:true,updated})
  }catch(error){return Response.json({ok:false,error:error instanceof Error?error.message:'Erro inesperado.'},{status:400})}
})
