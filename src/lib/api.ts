import { supabase } from './supabase'
import type { Client, Financial, Relationship, Visit } from './types'

const displayDate = (value: string | null) => value ? new Intl.DateTimeFormat('pt-BR').format(new Date(`${value}T12:00:00`)) : 'Não informado'

export async function fetchWorkspaceData(): Promise<{ clients: Client[]; visits: Visit[] }> {
  if (!supabase) return { clients: [], visits: [] }
  const [clientResult, visitResult] = await Promise.all([
    supabase.from('clients').select('*').order('site_name'),
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
    contact: { name: row.primary_contact_name ? String(row.primary_contact_name) : null, role: row.primary_contact_role ? String(row.primary_contact_role) : null, phone: row.primary_contact_phone ? String(row.primary_contact_phone) : null, email: row.primary_contact_email ? String(row.primary_contact_email) : null },
  }))
  const visits: Visit[] = (visitResult.data ?? []).map((row: Record<string, unknown>) => {
    const profile = row.profiles as { full_name?: string } | null
    return { id:String(row.id),clientId:String(row.client_id),date:String(row.visit_date),time:String(row.visit_time ?? ''),accountManager:profile?.full_name ?? String(row.original_representative_name),status:row.status as Visit['status'],receivedBy:String(row.received_by),receivedByRole:row.received_by_role as Visit['receivedByRole'],relationship:row.relationship as Relationship,viewedTicketReport:Boolean(row.viewed_ticket_report),hasComplaint:Boolean(row.has_complaint),complaint:row.complaint_description ? String(row.complaint_description) : undefined,notes:String(row.topics_and_solutions ?? ''),nextVisitDate:row.next_visit_date ? String(row.next_visit_date) : undefined }
  })
  return { clients, visits }
}
