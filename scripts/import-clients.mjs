import { readFile } from 'node:fs/promises'
import { createClient } from '@supabase/supabase-js'

const url = process.env.VITE_SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
if (!url || !serviceKey) throw new Error('Defina VITE_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY.')

const source = JSON.parse(await readFile(new URL('../supabase/import/clients.json', import.meta.url), 'utf8'))
const supabase = createClient(url, serviceKey, { auth: { persistSession: false } })
const rows = source.map((c) => ({
  source_sheet_id: process.env.GOOGLE_SHEET_ID,
  source_sheet_name: 'Perfil do Cliente',
  source_row: c.sheetRow,
  status: c.status,
  start_date: c.startDate,
  end_date: c.endDate,
  contract_number: c.contractNumber,
  legal_name: c.legalName,
  site_name: c.siteName,
  administrator: c.administrator,
  segment: c.segment,
  quantity: c.quantity,
  contract_value: c.contractValue,
  state: c.state,
  current_account_manager: c.accountManager,
  relationship: c.relationship,
  financial_status: c.financial,
  last_fleet_change: c.lastFleetChange,
  adjustment: c.adjustment == null ? null : String(c.adjustment),
  ticket_report_url: c.ticketReportUrl,
  trello_url: c.trelloUrl,
  sla: c.sla,
  misuse_history: c.misuseHistory,
  logistics_complexity: c.logisticsComplexity,
  training: c.training,
  legacy_last_contact: c.lastContactLegacy,
  address: c.address,
  primary_contact_name: c.contact.name,
  primary_contact_role: c.contact.role,
  primary_contact_phone: c.contact.phone,
  primary_contact_email: c.contact.email,
  sheet_sync_status: 'synced',
  sheet_synced_at: new Date().toISOString(),
}))

for (let i = 0; i < rows.length; i += 50) {
  const batch = rows.slice(i, i + 50)
  const { error } = await supabase.from('clients').upsert(batch, { onConflict: 'source_row' })
  if (error) throw error
  console.log(`Importados ${Math.min(i + batch.length, rows.length)} de ${rows.length}`)
}
console.log(`Importação concluída: ${rows.length} clientes.`)
