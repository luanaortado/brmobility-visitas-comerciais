import { supabase } from './supabase'
import type { Client, CurrentUser, Financial, Relationship, TimelineEvent, Visit, VisitMotive } from './types'

const displayDate = (value: string | null) => value ? new Intl.DateTimeFormat('pt-BR').format(new Date(`${value}T12:00:00`)) : 'Não informado'

export async function fetchWorkspaceData(): Promise<{ clients: Client[]; visits: Visit[]; currentUser: CurrentUser | null }> {
  if (!supabase) return { clients: [], visits: [], currentUser: null }
  const {data:{user}}=await supabase.auth.getUser()
  const clientResult=await supabase.rpc('get_visible_clients')
  if (clientResult.error) throw clientResult.error
  const [visitResult, profileResult, contactResult, timelineResult, noteResult] = await Promise.all([
    supabase.from('visits').select('*').order('visit_date', { ascending: false }),
    user ? supabase.from('profiles').select('*').eq('id',user.id).maybeSingle() : Promise.resolve({data:null,error:null}),
    supabase.from('client_contacts').select('*').eq('active',true).order('is_primary',{ascending:false}),
    supabase.from('client_timeline').select('*').order('occurred_at',{ascending:false}).limit(1000),
    supabase.from('client_notes').select('client_id,note'),
  ])
  const allContacts=(contactResult.data??[]) as Record<string,unknown>[]
  const timeline=(timelineResult.data??[]) as Record<string,unknown>[]
  const visitsRaw=(visitResult.error?[]:visitResult.data??[]) as Record<string,unknown>[]
  const clients: Client[] = (clientResult.data ?? []).map((row: Record<string, unknown>) => {
    const clientVisits=visitsRaw.filter(v=>v.client_id===row.id)
    const completed=clientVisits.filter(v=>v.status==='Realizada').map(v=>String(v.visit_date)).sort().reverse()[0]??null
    const upcoming=clientVisits.filter(v=>['Programada','Reagendada'].includes(String(v.status))).map(v=>String(v.visit_date)).sort()[0]??null
    const contacts=allContacts.filter(c=>c.client_id===row.id).map(c=>({id:String(c.id),name:c.name?String(c.name):null,role:c.role?String(c.role):null,phone:c.phone?String(c.phone):null,email:c.email?String(c.email):null,isPrimary:Boolean(c.is_primary),active:Boolean(c.active)}))
    return ({
    id: String(row.id), sheetRow: Number(row.source_row), status: String(row.status ?? 'Ativo'),
    startDateFormatted: displayDate(row.start_date as string | null), endDateFormatted: displayDate(row.end_date as string | null),
    contractNumber: String(row.contract_number ?? 'Não informado'), legalName: String(row.legal_name), siteName: String(row.site_name),
    administrator: String(row.administrator ?? 'Não informado'), segment: String(row.segment ?? 'Não informado'), quantity: Number(row.quantity ?? 0),
    contractValue: row.contract_value == null ? null : Number(row.contract_value), state: String(row.state ?? '—'), accountManager: String(row.current_account_manager ?? 'Não atribuído'),
    relationship: row.relationship as Relationship, financial: row.financial_status as Financial, lastFleetChange: row.last_fleet_change ? String(row.last_fleet_change) : null,
    ticketReportUrl: String(row.ticket_report_url ?? ''), trelloUrl: row.trello_url ? String(row.trello_url) : null,
    sla: String(row.sla ?? 'Não informado'), misuseHistory: String(row.misuse_history ?? 'Não informado'), logisticsComplexity: String(row.logistics_complexity ?? 'Não informado'),
    training: String(row.training ?? 'Não informado'), lastContact: row.legacy_last_contact ? String(row.legacy_last_contact) : null, address: row.address ? String(row.address) : null,
    lastVisit:completed,nextVisit:upcoming,
    managementNote: String(((noteResult.data??[]) as Record<string,unknown>[]).find(n=>n.client_id===row.id)?.note??''),
    contact: contacts.find(c=>c.isPrimary)??{ name: row.primary_contact_name ? String(row.primary_contact_name) : null, role: row.primary_contact_role ? String(row.primary_contact_role) : null, phone: row.primary_contact_phone ? String(row.primary_contact_phone) : null, email: row.primary_contact_email ? String(row.primary_contact_email) : null,isPrimary:true },
    contacts,
    timeline:timeline.filter(t=>t.client_id===row.id).map((t):TimelineEvent=>({id:String(t.id),clientId:String(t.client_id),event:String(t.event_type),field:t.field_name?String(t.field_name):undefined,oldValue:t.old_value?String(t.old_value):undefined,newValue:t.new_value?String(t.new_value):undefined,actor:String(t.actor_name??'Sistema'),source:String(t.source??'app'),occurredAt:String(t.occurred_at)})),
  })})
  const visits: Visit[] = (visitResult.error ? [] : visitResult.data ?? []).map((row: Record<string, unknown>) => {
    return { id:String(row.id),clientId:String(row.client_id),date:String(row.visit_date),time:String(row.visit_time ?? ''),accountManager:String(row.original_representative_name ?? 'Não informado'),status:row.status as Visit['status'],receivedBy:String(row.received_by),receivedByRole:row.received_by_role as Visit['receivedByRole'],relationship:row.relationship as Relationship,viewedTicketReport:Boolean(row.viewed_ticket_report),hasComplaint:Boolean(row.has_complaint),complaint:row.complaint_description ? String(row.complaint_description) : undefined,notes:String(row.topics_and_solutions ?? ''),nextVisitDate:row.next_visit_date ? String(row.next_visit_date) : undefined,motive:row.visit_motive as VisitMotive,opportunityIdentified:Boolean(row.opportunity_identified),opportunityDescription:row.opportunity_description?String(row.opportunity_description):undefined }
  })
  const p=profileResult.data as Record<string,unknown>|null
  const role=(p?.role??'representative') as CurrentUser['role']
  const elevated=role==='admin'||role==='manager'
  const currentUser:CurrentUser|null=p?{id:String(p.id),fullName:String(p.full_name),role,active:Boolean(p.active),permissions:{viewFinancial:elevated||Boolean(p.can_view_financial),editFinancial:elevated||Boolean(p.can_edit_financial),viewContractValue:elevated||Boolean(p.can_view_contract_value),editProfile:elevated||Boolean(p.can_edit_profile),editContacts:elevated||Boolean(p.can_edit_contacts),recordVisits:elevated||Boolean(p.can_record_visits),manageUsers:role==='admin'}}:null
  return { clients, visits, currentUser }
}

export async function saveClientNote(clientId:string,note:string) {
  if(!supabase) throw new Error('Ambiente seguro indisponível.')
  const {data:{user}}=await supabase.auth.getUser()
  if(!user) throw new Error('Sessão expirada.')
  const {error}=await supabase.from('client_notes').upsert({client_id:clientId,note:note.trim(),updated_by:user.id,updated_at:new Date().toISOString()},{onConflict:'client_id'})
  if(error) throw error
}

export async function syncClientContact(clientId:string,contact:{name:string;role:string;phone:string;email:string}) {
  if(!supabase) throw new Error('Ambiente seguro indisponível.')
  const {data:{user}}=await supabase.auth.getUser()
  const {data:existing}=await supabase.from('client_contacts').select('id').eq('client_id',clientId).eq('is_primary',true).eq('active',true).maybeSingle()
  const payload={client_id:clientId,name:contact.name.trim(),role:contact.role.trim()||null,phone:contact.phone.trim()||null,email:contact.email.trim()||null,is_primary:true,active:true,created_by:user?.id}
  const result=existing?.id?await supabase.from('client_contacts').update({...payload,updated_at:new Date().toISOString()}).eq('id',existing.id):await supabase.from('client_contacts').insert(payload).select('id').single()
  if(result.error) throw result.error
  const contactId=existing?.id??result.data?.id
  const {error:rpcError}=await supabase.rpc('set_primary_contact',{target_contact_id:contactId})
  if(rpcError)throw rpcError
  await supabase.functions.invoke('sync-client',{body:{clientId}})
}

export async function addClientContact(clientId:string,contact:{name:string;role:string;phone:string;email:string},makePrimary=false){
  if(!supabase)throw new Error('Ambiente seguro indisponível.')
  const {data:{user}}=await supabase.auth.getUser()
  const {data,error}=await supabase.from('client_contacts').insert({client_id:clientId,name:contact.name.trim(),role:contact.role.trim()||null,phone:contact.phone.trim()||null,email:contact.email.trim()||null,is_primary:false,active:true,created_by:user?.id}).select('id').single()
  if(error)throw error
  if(makePrimary){const {error:primaryError}=await supabase.rpc('set_primary_contact',{target_contact_id:data.id});if(primaryError)throw primaryError;await supabase.functions.invoke('sync-client',{body:{clientId}})}
}

export async function setPrimaryContact(clientId:string,contactId:string){
  if(!supabase)throw new Error('Ambiente seguro indisponível.')
  const {error}=await supabase.rpc('set_primary_contact',{target_contact_id:contactId})
  if(error)throw error
  await supabase.functions.invoke('sync-client',{body:{clientId}})
}

export async function inviteUser(input:{email:string;fullName:string;role:string}){
  if(!supabase)throw new Error('Ambiente seguro indisponível.')
  const {data,error}=await supabase.functions.invoke('invite-user',{body:input})
  if(error||!data?.ok)throw error??new Error(data?.error??'Não foi possível enviar o convite.')
}

export async function updateClientManagementProfile(clientId:string,input:{relationship:Relationship;financial:Financial;training:'Sim'|'Não';accountManager:string;lastFleetChange:string}) {
  if(!supabase) throw new Error('Ambiente seguro indisponível.')
  const {error}=await supabase.rpc('update_client_management_profile',{
    target_client_id:clientId,
    new_relationship:input.relationship,
    new_financial:input.financial,
    new_training:input.training,
    new_account_manager:input.accountManager.trim(),
    new_last_fleet_change:input.lastFleetChange?`${input.lastFleetChange}-01`:null,
  })
  if(error) throw error
  await supabase.functions.invoke('sync-client',{body:{clientId}})
}

export async function createVisit(input:{clientId:string;visitDate:string;visitTime:string;receivedBy:string;receivedByRole:string;relationship:string;viewedTicketReport:boolean;hasComplaint:boolean;complaintDescription:string;topicsAndSolutions:string;nextVisitDate:string;motive?:VisitMotive;opportunityIdentified?:boolean;opportunityDescription?:string}) {
  if(!supabase) throw new Error('Ambiente seguro indisponível.')
  const {data:{user}}=await supabase.auth.getUser()
  if(!user) throw new Error('Sessão expirada.')
  const {data:profile}=await supabase.from('profiles').select('full_name').eq('id',user.id).single()
  const {error}=await supabase.from('visits').insert({client_id:input.clientId,representative_id:user.id,visit_date:input.visitDate,visit_time:input.visitTime||null,status:'Realizada',received_by:input.receivedBy,received_by_role:input.receivedByRole,relationship:input.relationship,viewed_ticket_report:input.viewedTicketReport,has_complaint:input.hasComplaint,complaint_description:input.hasComplaint?input.complaintDescription:null,topics_and_solutions:input.topicsAndSolutions,next_visit_date:input.nextVisitDate||null,visit_motive:input.motive??'Relacionamento',opportunity_identified:Boolean(input.opportunityIdentified),opportunity_description:input.opportunityIdentified?input.opportunityDescription:null,original_representative_name:profile?.full_name??user.email??'Usuário'})
  if(error) throw error
}

export async function scheduleVisit(input:{clientId:string;visitDate:string;visitTime:string;receivedBy:string;relationship:string;agenda:string}) {
  if(!supabase) throw new Error('Ambiente seguro indisponível.')
  const {data:{user}}=await supabase.auth.getUser()
  if(!user) throw new Error('Sessão expirada.')
  const {data:profile}=await supabase.from('profiles').select('full_name').eq('id',user.id).single()
  const {error}=await supabase.from('visits').insert({
    client_id:input.clientId,
    representative_id:user.id,
    visit_date:input.visitDate,
    visit_time:input.visitTime||null,
    status:'Programada',
    received_by:input.receivedBy,
    received_by_role:'Gestor',
    relationship:input.relationship,
    viewed_ticket_report:false,
    has_complaint:false,
    topics_and_solutions:input.agenda.trim()||'Sem pauta informada',
    original_representative_name:profile?.full_name??user.email??'Usuário',
  })
  if(error) throw error
}
