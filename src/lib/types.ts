export type Relationship = 'Excelente' | 'Sensível' | 'Crítico'
export type Financial = 'Adimplente' | 'Inadimplência Moderada' | 'Inadimplente Crítico'
export type VisitStatus = 'Realizada' | 'Programada' | 'Atrasada' | 'Cancelada' | 'Reagendada'
export type VisitMotive = 'Relacionamento' | 'Acompanhamento operacional' | 'Reclamação' | 'Renovação' | 'Expansão/Nova oportunidade' | 'Treinamento' | 'Outro'

export interface Contact {
  id?: string
  name: string | null
  role: string | null
  phone: string | null
  email: string | null
  isPrimary?: boolean
  active?: boolean
}

export interface TimelineEvent {
  id: string
  clientId: string
  event: string
  field?: string
  oldValue?: string
  newValue?: string
  actor: string
  source: string
  occurredAt: string
}

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
  lastFleetChange?: string | null
  ticketReportUrl: string
  trelloUrl: string | null
  sla: string
  misuseHistory: string
  logisticsComplexity: string
  training: string
  lastContact: string | null
  lastVisit?: string | null
  nextVisit?: string | null
  address: string | null
  managementNote?: string
  contact: Contact
  contacts?: Contact[]
  timeline?: TimelineEvent[]
}

export interface Visit {
  id: string
  clientId: string
  date: string
  time: string
  accountManager: string
  status: VisitStatus
  receivedBy: string
  receivedByRole: 'Gestor' | 'Coordenador' | 'Supervisor'
  relationship: Relationship
  viewedTicketReport: boolean
  hasComplaint: boolean
  complaint?: string
  notes: string
  nextVisitDate?: string
  motive?: VisitMotive
  opportunityIdentified?: boolean
  opportunityDescription?: string
  meetingMode?: 'Presencial' | 'Videoconferência'
}

export interface CurrentUser {
  id: string
  fullName: string
  role: 'admin' | 'manager' | 'supervisor' | 'representative' | 'viewer'
  active: boolean
  permissions: {
    viewFinancial: boolean
    editFinancial: boolean
    viewContractValue: boolean
    editProfile: boolean
    editContacts: boolean
    recordVisits: boolean
    manageUsers: boolean
  }
}
