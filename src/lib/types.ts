export type Relationship = 'Excelente' | 'Sensível' | 'Crítico'
export type Financial = 'Adimplente' | 'Inadimplência Moderada' | 'Inadimplente Crítico'

export interface Client {
  id: string
  sheetRow: number
  status: string
  startDateFormatted: string
  endDateFormatted: string
  contractNumber: string
  legalName: string
  siteName: string
  administrator: string
  segment: string
  quantity: number
  contractValue: number | null
  state: string
  accountManager: string
  relationship: Relationship
  financial: Financial
  ticketReportUrl: string
  trelloUrl: string | null
  sla: string
  misuseHistory: string
  logisticsComplexity: string
  training: string
  lastContact: string | null
  address: string | null
  contact: { name: string | null; role: string | null; phone: string | null; email: string | null }
}

export interface Visit {
  id: string
  clientId: string
  date: string
  time: string
  accountManager: string
  status: 'Realizada' | 'Programada' | 'Atrasada'
  receivedBy: string
  receivedByRole: 'Gestor' | 'Coordenador' | 'Supervisor'
  relationship: Relationship
  viewedTicketReport: boolean
  hasComplaint: boolean
  complaint?: string
  notes: string
  nextVisitDate?: string
}
