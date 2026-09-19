import { createClient } from 'npm:@supabase/supabase-js@2'

// Scheduled/webhook import. The UUID written in column AB is the only matching key.
Deno.serve(async req=>{
  try{
    if(req.headers.get('x-sync-secret')!==Deno.env.get('SHEET_SYNC_SECRET'))throw new Error('Não autorizado.')
    const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}})
    const response=await fetch(Deno.env.get('APPS_SCRIPT_URL')!,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({secret:Deno.env.get('SHEET_SYNC_SECRET'),action:'pullSheet',sheetName:Deno.env.get('GOOGLE_SHEET_TAB')??'Perfil do Cliente'})})
    const result=await response.json();if(!response.ok||!result.ok)throw new Error(result.error??`Falha ao ler planilha (${response.status}).`)
    const values=result.values??[];let updated=0
    for(const row of values){
      const [name,role,phone,email,permanentId,relationship,financial,training,manager,fleet]=row
      if(!permanentId)continue
      const {data:current}=await db.from('clients').select('sync_updated_at').eq('permanent_id',permanentId).maybeSingle()
      const sheetUpdated=req.headers.get('x-sheet-updated-at')??new Date().toISOString()
      if(current&&new Date(current.sync_updated_at)>new Date(sheetUpdated))continue
      const patch:Record<string,unknown>={primary_contact_name:name||null,primary_contact_role:role||null,primary_contact_phone:phone||null,primary_contact_email:email||null,sync_source:'sheet',sync_updated_at:sheetUpdated,sheet_sync_status:'synced',sheet_synced_at:new Date().toISOString()}
      if(['Excelente','Sensível','Crítico'].includes(relationship))patch.relationship=relationship
      if(['Adimplente','Inadimplência Moderada','Inadimplente Crítico'].includes(financial))patch.financial_status=financial
      if(['Sim','Não'].includes(training))patch.training=training
      if(manager)patch.current_account_manager=manager
      if(/^\d{4}-\d{2}/.test(fleet??''))patch.last_fleet_change=`${fleet.slice(0,7)}-01`
      const {error}=await db.from('clients').update(patch).eq('permanent_id',permanentId)
      if(!error)updated++
    }
    return Response.json({ok:true,updated})
  }catch(error){return Response.json({ok:false,error:error instanceof Error?error.message:'Erro inesperado.'},{status:400})}
})
