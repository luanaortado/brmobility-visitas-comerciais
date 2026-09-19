import { createClient } from 'npm:@supabase/supabase-js@2'

// One-time/idempotent rollout: publishes the database UUID to column AB.
Deno.serve(async req=>{
  try{
    if(req.headers.get('x-sync-secret')!==Deno.env.get('SHEET_SYNC_SECRET'))throw new Error('Não autorizado.')
    const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}})
    const {data:clients,error}=await db.from('clients').select('id,permanent_id,source_row,source_sheet_name').not('source_row','is',null)
    if(error)throw error
    const sheetName=Deno.env.get('GOOGLE_SHEET_TAB')??'3 Perfil do Cliente'
    const response=await fetch(Deno.env.get('APPS_SCRIPT_URL')!,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({secret:Deno.env.get('SHEET_SYNC_SECRET'),action:'backfillIds',clients:(clients??[]).map(client=>({row:client.source_row,permanentId:client.permanent_id,sheetName}))})})
    const result=await response.json();if(!response.ok||!result.ok)throw new Error(result.error??`Falha ao gravar os IDs (${response.status}).`)
    return Response.json(result)
  }catch(error){return Response.json({ok:false,error:error instanceof Error?error.message:'Erro inesperado.'},{status:400})}
})
