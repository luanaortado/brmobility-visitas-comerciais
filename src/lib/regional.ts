import type { Visit } from './types'
export const VISIT_FEE = 90
export const REGIONAL_STATES = ['PE','PA','CE','BA','GO','DF']
export const REGIONAL_REPORT_STATES = [...REGIONAL_STATES,'RJ']
export const REGIONALS = [
  {key:'tiago-pe',name:'Tiago',area:'PE',states:['PE'],aliases:['Tiago','Tiago PE','Tiago (PE)'],planName:'Tiago',billable:true},
  {key:'matson-pa',name:'Matson',area:'PA',states:['PA'],aliases:['Matson'],planName:'Matson',billable:true},
  {key:'tarcisio-ce',name:'Tarcísio',area:'CE',states:['CE'],aliases:['Tarcísio','Tarcisio'],planName:'Tarcísio',billable:true},
  {key:'gaspar-ba',name:'Gaspar',area:'BA',states:['BA'],aliases:['Gaspar','Vinícius Gaspar','Vinicius Gaspar'],planName:'Gaspar',billable:true},
  {key:'tiago-go-df',name:'Tiago',area:'GO/DF',states:['GO','DF'],aliases:['Tiago','Tiago GO','Tiago (GO)'],planName:'Tiago (GO)',billable:true},
  {key:'leonardo-rj',name:'Leonardo',area:'RJ',states:['RJ'],aliases:['Leonardo','Leonardo Nogueira'],planName:'Leonardo',billable:false},
  {key:'comercial-local',name:'Comercial Local',area:'Octávio + Luana',states:[],aliases:['Octávio','Octavio','Octávio Ortado','Octavio Ortado','Luana','Luana Ortado'],planName:'Comercial Local',billable:false},
] as const
export interface RegionalChecklist {
  visit_id: string; operations_contact: boolean; duration_minutes: number;
  misuse: string; training: string; improvements: string; actions: string;
  email_recipient: string; email_sent_on: string; email_evidence: string;
  status: 'Pendente' | 'Ajustar' | 'Aprovada'; review_note: string;
  submitted_at?: string; reviewed_at?: string; reviewed_by?: string;
}
export interface MonthlyPlan {client_id:string; period:string; regional_name:string; planned_date:string; id?:string}
export function emptyChecklist(visitId: string): RegionalChecklist {
  return {visit_id:visitId,operations_contact:false,duration_minutes:0,misuse:'',training:'',improvements:'',actions:'',email_recipient:'',email_sent_on:'',email_evidence:'',status:'Pendente',review_note:''}
}
export function monthEnd(period:string) {
  const [year,month]=period.split('-').map(Number)
  return `${period}-${String(new Date(Date.UTC(year,month,0)).getUTCDate()).padStart(2,'0')}`
}
export function localDate(timestamp:string) {
  return new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(timestamp))
}
export function withinCutoff(row:RegionalChecklist,period:string) {
  return Boolean(row.submitted_at && localDate(row.submitted_at)<=monthEnd(period) && row.email_sent_on && row.email_sent_on<=monthEnd(period))
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
export function regionalForVisit(state:string,accountManager:string) {
  return REGIONALS.find(item=>matchesRegionalIdentity(state,accountManager,item.key))
}
export function matchesPlan(visit:Visit,plan:MonthlyPlan) {
  return visit.clientId===plan.client_id && visit.date.startsWith(plan.period.slice(0,7)) && normalizeAtName(visit.accountManager)===normalizeAtName(plan.regional_name)
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
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(row.email_recipient) || !row.email_sent_on || row.email_sent_on < visit.date || !row.email_evidence.trim()) missing.push('E-mail ao anfitrião com comprovante')
  return missing
}
export function validatedVisits(visits: Visit[], rows: RegionalChecklist[], plans:MonthlyPlan[],period:string) {
  const seen=new Set<string>()
  return visits.filter(v=>plans.some(p=>matchesPlan(v,p)&&p.period.slice(0,7)===period)&&rows.some(r=>r.visit_id===v.id && r.status==='Aprovada' && missingCriteria(v,r).length===0 && withinCutoff(r,period))).sort((a,b)=>a.date.localeCompare(b.date)||a.id.localeCompare(b.id)).filter(v=>{const key=`${v.clientId}:${v.date.slice(0,7)}`;if(seen.has(key))return false;seen.add(key);return true})
}
export function csvCell(value: unknown) {const s=String(value??'');return `"${(/^[=+\-@\t\r]/.test(s)?"'":'')+s.replaceAll('"','""')}"`}
export function visitReport(visits:Visit[],rows:RegionalChecklist[],plans:MonthlyPlan[],period:string,siteName:(id:string)=>string,regionalName:(visit:Visit)=>string=visit=>visit.accountManager) {
  const included=new Set(validatedVisits(visits,rows,plans,period).map(v=>v.id))
  return [['Mês','AT','Posto','Data prevista','Data da visita','Quem recebeu','Cargo','Duração (min)','Chamados apresentados','Reclamações','Pauta','Mau uso','Treinamento','Melhorias','Encaminhamentos','E-mail do anfitrião','Data do e-mail','Comprovante','Registro enviado em','Status','Revisado em','Observação','Valor a receber (R$)'],...visits.map(v=>{const r=rows.find(x=>x.visit_id===v.id),p=plans.find(x=>matchesPlan(v,x));return [period,regionalName(v),siteName(v.clientId),p?.planned_date??'',v.date,v.receivedBy,v.receivedByRole,r?.duration_minutes??'',v.viewedTicketReport?'Sim':'Não',v.hasComplaint?v.complaint:'Sem reclamações',v.notes,r?.misuse,r?.training,r?.improvements,r?.actions,r?.email_recipient,r?.email_sent_on,r?.email_evidence,r?.submitted_at,r?.status??'Sem checklist',r?.reviewed_at,r?.review_note,included.has(v.id)?VISIT_FEE:0]})]
}
