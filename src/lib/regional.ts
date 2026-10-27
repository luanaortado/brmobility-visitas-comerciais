import type { Visit } from './types'
export const VISIT_FEE = 90
export const REGIONAL_STATES = ['PE','PA','CE','BA','GO','DF']
export const REGIONAL_REPORT_STATES = [...REGIONAL_STATES,'RJ']
export interface RegionalDefinition {key:string;name:string;area:string;states:readonly string[];aliases:readonly string[];planName:string;billable:boolean;invoice:boolean;trello:boolean;travel?:boolean;emailRequired?:boolean}
export const REGIONALS = [
  {key:'tiago-pe',name:'Tiago',area:'PE',states:['PE'],aliases:['Tiago','Tiago PE','Tiago (PE)','Tiago Fernandes'],planName:'Tiago Fernandes da Silva',billable:true,invoice:true,trello:false},
  {key:'matson-pa',name:'Matson',area:'PA',states:['PA'],aliases:['Matson'],planName:'Matson Kleber Vaz de Souza',billable:true,invoice:true,trello:false},
  {key:'tarcisio-ce',name:'Tarcísio',area:'CE',states:['CE'],aliases:['Tarcísio','Tarcisio'],planName:'Tarcísio Alves de Lima Junior',billable:true,invoice:true,trello:false},
  {key:'gaspar-ba',name:'Gaspar',area:'BA',states:['BA'],aliases:['Gaspar','Vinícius Gaspar','Vinicius Gaspar'],planName:'Vinicius Gaspar Manso',billable:true,invoice:false,trello:false},
  {key:'tiago-go-df',name:'Tiago',area:'GO/DF',states:['GO','DF'],aliases:['Tiago','Tiago GO','Tiago (GO)','Tiago Lopes'],planName:'Tiago Lopes Ferreira',billable:true,invoice:true,trello:false,travel:true},
  {key:'leonardo-rj',name:'Leonardo',area:'RJ',states:['RJ'],aliases:['Leonardo','Leonardo Nogueira'],planName:'Leonardo da Silva Nogueira',billable:false,invoice:true,trello:true,emailRequired:true},
  {key:'comercial-local',name:'Comercial Local',area:'Octávio + Luana',states:[],aliases:['Octávio','Octavio','Octávio Augusto','Octávio Ortado','Octavio Ortado','Luana','Luana Ortado'],planName:'Octávio Augusto',billable:false,invoice:false,trello:true,emailRequired:true},
] as const
export interface RegionalChecklist {
  visit_id: string; operations_contact: boolean; duration_minutes: number;
  misuse: string; training: string; improvements: string; actions: string;
  email_recipient: string; email_sent_on: string; email_evidence: string; email_formalized: boolean;
  travel_amount: number; travel_note: string; travel_approved?: boolean;
  status: 'Pendente' | 'Ajustar' | 'Aprovada'; review_note: string;
  submitted_at?: string; reviewed_at?: string; reviewed_by?: string;
  payment_status?: 'Pendente' | 'NF Solicitada' | 'NF Recebida' | 'Enviado ao Financeiro' | 'Pago' | 'Não se aplica'; payment_sent_at?: string; paid_at?: string;
}
export interface MonthlyPlan {client_id:string; period:string; regional_name:string; planned_date?:string|null; id?:string; guidance:string; priority:'Alta'|'Média'; source:'Manual'; relationship_reason?:boolean; ticket_volume_reason?:boolean}
export function emptyChecklist(visitId: string): RegionalChecklist {
  return {visit_id:visitId,operations_contact:false,duration_minutes:0,misuse:'',training:'',improvements:'',actions:'',email_recipient:'',email_sent_on:'',email_evidence:'',email_formalized:false,travel_amount:0,travel_note:'',status:'Pendente',review_note:''}
}
export function monthEnd(period:string) {
  const [year,month]=period.split('-').map(Number)
  return `${period}-${String(new Date(Date.UTC(year,month,0)).getUTCDate()).padStart(2,'0')}`
}
export function localDate(timestamp:string) {
  return new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(timestamp))
}
export function requiresEmailForVisit(visit:Pick<Visit,'accountManager'>) {
  const name=normalizeAtName(visit.accountManager)
  return name.startsWith('leonardo')||name.startsWith('octavio')
}
export function withinCutoff(row:RegionalChecklist,period:string,emailRequired=true) {
  return Boolean(row.submitted_at && localDate(row.submitted_at)<=monthEnd(period) && (!emailRequired || row.email_formalized))
}
export function normalizeAtName(value:string) {
  return value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('pt-BR').replace(/[^a-z0-9]+/g,' ').trim().replace(/\s+/g,' ')
}
export function matchesRegionalIdentity(state:string,accountManager:string,regionalKey:string) {
  const definition=REGIONALS.find(item=>item.key===regionalKey)
  if(!definition||(definition.states.length>0&&!definition.states.includes(state.toUpperCase() as never)))return false
  const manager=normalizeAtName(accountManager)
  return definition.aliases.some(alias=>{const normalized=normalizeAtName(alias);return manager===normalized||manager.startsWith(`${normalized} `)||manager.endsWith(` ${normalized}`)})
}
export function regionalForVisit(state:string,accountManager:string):RegionalDefinition|undefined {
  return REGIONALS.find(item=>matchesRegionalIdentity(state,accountManager,item.key))
}
export function matchesPlan(visit:Visit,plan:MonthlyPlan) {
  const visitName=normalizeAtName(visit.accountManager),planName=normalizeAtName(plan.regional_name)
  return visit.clientId===plan.client_id && visit.date.startsWith(plan.period.slice(0,7)) && (visitName===planName||visitName.startsWith(`${planName} `)||planName.startsWith(`${visitName} `))
}
export function existingMonthVisits(visits:Visit[],clients:{id:string;state:string}[],period:string,at:string) {
  return visits.filter(v=>{
    const client=clients.find(c=>c.id===v.clientId),state=client?.state.toUpperCase()??''
    if(v.status!=='Realizada'||!v.date.startsWith(period))return false
    if(at==='comercial-local')return matchesRegionalIdentity(state,v.accountManager,at)
    if(!at)return Boolean(regionalForVisit(state,v.accountManager))
    if(!REGIONAL_REPORT_STATES.includes(state))return false
    const definition=REGIONALS.find(item=>item.key===at)
    return definition?matchesRegionalIdentity(state,v.accountManager,definition.key):normalizeAtName(v.accountManager)===normalizeAtName(at)
  })
}
export function missingCriteria(visit: Visit, row: RegionalChecklist) {
  const missing: string[] = []
  if(visit.status !== 'Realizada' || visit.meetingMode === 'Videoconferência') missing.push('Visita presencial realizada')
  if(!visit.receivedBy.trim() || !['Gestor','Supervisor'].includes(visit.receivedByRole) || !row.operations_contact) missing.push('Gestor ou supervisor de operações')
  if(!(row.duration_minutes > 0 && row.duration_minutes <= 15)) missing.push('Duração de até 15 minutos')
  if(!visit.viewedTicketReport || !visit.notes.trim() || (visit.hasComplaint && !visit.complaint?.trim()) || !row.misuse.trim() || !row.training.trim() || !row.improvements.trim() || !row.actions.trim()) missing.push('Pauta e encaminhamentos completos')
  if(requiresEmailForVisit(visit) && (!row.email_formalized || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(row.email_recipient))) missing.push('Formalização por e-mail')
  return missing
}
export function validatedVisits(visits: Visit[], rows: RegionalChecklist[], plans:MonthlyPlan[],period:string) {
  const seen=new Set<string>()
  return visits.filter(v=>plans.some(p=>matchesPlan(v,p)&&p.period.slice(0,7)===period)&&rows.some(r=>r.visit_id===v.id && r.status==='Aprovada' && missingCriteria(v,r).length===0 && withinCutoff(r,period,requiresEmailForVisit(v)))).sort((a,b)=>a.date.localeCompare(b.date)||a.id.localeCompare(b.id)).filter(v=>{const key=`${v.clientId}:${v.date.slice(0,7)}`;if(seen.has(key))return false;seen.add(key);return true})
}
export function csvCell(value: unknown) {const s=String(value??'');return `"${(/^[=+\-@\t\r]/.test(s)?"'":'')+s.replaceAll('"','""')}"`}
export function visitReport(visits:Visit[],rows:RegionalChecklist[],plans:MonthlyPlan[],period:string,siteName:(id:string)=>string,regionalName:(visit:Visit)=>string=visit=>visit.accountManager) {
  const included=new Set(validatedVisits(visits,rows,plans,period).map(v=>v.id))
  return [['Mês','AT','Posto','Data prevista','Data da visita','Quem recebeu','Cargo','Duração (min)','Chamados apresentados','Reclamações','Pauta','Mau uso','Treinamento','Melhorias','Encaminhamentos','E-mail do anfitrião','Formalizada por e-mail','Registro enviado em','Status','Pagamento','Deslocamento (R$)','Revisado em','Observação','Valor da visita (R$)'],...visits.map(v=>{const r=rows.find(x=>x.visit_id===v.id),p=plans.find(x=>matchesPlan(v,x));return [period,regionalName(v),siteName(v.clientId),p?.planned_date??'',v.date,v.receivedBy,v.receivedByRole,r?.duration_minutes??'',v.viewedTicketReport?'Sim':'Não',v.hasComplaint?v.complaint:'Sem reclamações',v.notes,r?.misuse,r?.training,r?.improvements,r?.actions,r?.email_recipient,r?.email_formalized?'Sim':'Não',r?.submitted_at,r?.status??'Sem checklist',r?.payment_status??'',r?.travel_approved?r.travel_amount:0,r?.reviewed_at,r?.review_note,included.has(v.id)?VISIT_FEE:0]})]
}

export function downloadVisitCalendar(visit:Visit,siteName:string) {
  const digits=(visit.time||'09:00').replace(':','').slice(0,4).padEnd(4,'0')
  const date=visit.date.replaceAll('-','')
  const start=`${date}T${digits}00`
  const endHour=String(Math.min(23,Number(digits.slice(0,2))+1)).padStart(2,'0')
  const end=`${date}T${endHour}${digits.slice(2)}00`
  const safe=(value:string)=>value.replace(/([,;])/g,'\\$1').replace(/\n/g,'\\n')
  const body=['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//BRMobility//Gestão de Carteira//PT-BR','BEGIN:VEVENT',`UID:${visit.id}@brmobility.com.br`,`DTSTART:${start}`,`DTEND:${end}`,`SUMMARY:${safe(`Visita/Reunião · ${siteName}`)}`,`DESCRIPTION:${safe(visit.notes||'Visita/reunião comercial')}`,'END:VEVENT','END:VCALENDAR'].join('\r\n')
  const url=URL.createObjectURL(new Blob([body],{type:'text/calendar;charset=utf-8'}))
  const link=document.createElement('a');link.href=url;link.download=`visita-${siteName.toLowerCase().replace(/[^a-z0-9]+/gi,'-')}.ics`;link.click();window.setTimeout(()=>URL.revokeObjectURL(url),1000)
}
