import { supabase } from './supabase'
import type { Client, Financial, Relationship, Visit } from './types'

const displayDate = (value: string | null) => value ? new Intl.DateTimeFormat('pt-BR').format(new Date(`${value}T12:00:00`)) : 'Não informado'

export async function fetchWorkspaceData(): Promise<{ clients: Client[]; visits: Visit[] }> {
  if (!supabase) return { clients: [], visits: [] }
  const [clientResult, visitResult] = await Promise.all([
    supabase.from('clients').select('*, client_notes(note)').order('site_name'),
    supabase.from('visits').select('*, profiles!visits_representative_id_fkey(full_name)').order('visit_date', { ascending: false }),
  ])
  if (clientResult.error) throw clientResult.error
  if (visitResult.error) throw visitResult.error
  const clients: Client[] = (clientResult.data ?? []).map((row: Record<string, unknown>) => ({
    id: String(row.id), sheetRow: Number(row.source_row), status: String(row.status ?? 'Ativo'),
    startDateFormatted: displayDate(row.start_date as string | null), endDateFormatted: displayDate(row.end_date as string | null),
    contractNumber: String(row.contract_number ?? 'Não informado'), legalName: String(row.legal_name), siteName: String(row.site_name),
    administrator: String(row.administrator ?? 'Não informado'), segment: String(row.segment ?? 'Não informado'), quantity: Number(row.quantity ?? 0),
    contractValue: row.contract_value == null ? null : Number(row.contract_value), state: String(row.state ?? '—'), accountManager: String(row.current_account_manager ?? 'Não atribuído'),
    relationship: row.relationship as Relationship, financial: row.financial_status as Financial,
    ticketReportUrl: String(row.ticket_report_url ?? ''), trelloUrl: row.trello_url ? String(row.trello_url) : null,
    sla: String(row.sla ?? 'Não informado'), misuseHistory: String(row.misuse_history ?? 'Não informado'), logisticsComplexity: String(row.logistics_complexity ?? 'Não informado'),
    training: String(row.training ?? 'Não informado'), lastContact: row.legacy_last_contact ? String(row.legacy_last_contact) : null, address: row.address ? String(row.address) : null,
    managementNote: Array.isArray(row.client_notes) && row.client_notes[0] ? String((row.client_notes[0] as {note?:string}).note ?? '') : '',
    contact: { name: row.primary_contact_name ? String(row.primary_contact_name) : null, role: row.primary_contact_role ? String(row.primary_contact_role) : null, phone: row.primary_contact_phone ? String(row.primary_contact_phone) : null, email: row.primary_contact_email ? String(row.primary_contact_email) : null },
  }))
  const visits: Visit[] = (visitResult.data ?? []).map((row: Record<string, unknown>) => {
    const profile = row.profiles as { full_name?: string } | null
    return { id:String(row.id),clientId:String(row.client_id),date:String(row.visit_date),time:String(row.visit_time ?? ''),accountManager:profile?.full_name ?? String(row.original_representative_name),status:row.status as Visit['status'],receivedBy:String(row.received_by),receivedByRole:row.received_by_role as Visit['receivedByRole'],relationship:row.relationship as Relationship,viewedTicketReport:Boolean(row.viewed_ticket_report),hasComplaint:Boolean(row.has_complaint),complaint:row.complaint_description ? String(row.complaint_description) : undefined,notes:String(row.topics_and_solutions ?? ''),nextVisitDate:row.next_visit_date ? String(row.next_visit_date) : undefined }
  })
  return { clients, visits }
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
  const {error}=await supabase.functions.invoke('sync-contact',{body:{clientId,...contact}})
  if(error) throw error
}

export async function createVisit(input:{clientId:string;visitDate:string;visitTime:string;receivedBy:string;receivedByRole:string;relationship:string;viewedTicketReport:boolean;hasComplaint:boolean;complaintDescription:string;topicsAndSolutions:string;nextVisitDate:string}) {
  if(!supabase) throw new Error('Ambiente seguro indisponível.')
  const {data:{user}}=await supabase.auth.getUser()
  if(!user) throw new Error('Sessão expirada.')
  const {data:profile}=await supabase.from('profiles').select('full_name').eq('id',user.id).single()
  const {error}=await supabase.from('visits').insert({client_id:input.clientId,representative_id:user.id,visit_date:input.visitDate,visit_time:input.visitTime||null,status:'Realizada',received_by:input.receivedBy,received_by_role:input.receivedByRole,relationship:input.relationship,viewed_ticket_report:input.viewedTicketReport,has_complaint:input.hasComplaint,complaint_description:input.hasComplaint?input.complaintDescription:null,topics_and_solutions:input.topicsAndSolutions,next_visit_date:input.nextVisitDate||null,original_representative_name:profile?.full_name??user.email??'Usuário'})
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
