import { useEffect, useState } from 'react'
import { AlertCircle, CalendarDays, CheckCircle2, ChevronRight, Clock3, Download, FileText, MapPin, WalletCards } from 'lucide-react'
import type { Client, CurrentUser, Visit } from '../lib/types'
import { downloadVisitCalendar, matchesPlan, normalizeAtName, regionalForVisit, REGIONALS } from '../lib/regional'
import type { MonthlyPlan, RegionalChecklist } from '../lib/regional'

type Bucket = 'to-visit' | 'scheduled' | 'validation' | 'payment' | 'done'

function belongsToUser(plan:MonthlyPlan,user:CurrentUser) {
  const userName=normalizeAtName(user.fullName),planName=normalizeAtName(plan.regional_name)
  if(userName===planName||userName.startsWith(`${planName} `)||planName.startsWith(`${userName} `))return true
  return REGIONALS.some(regional=>normalizeAtName(regional.planName)===planName&&regional.aliases.some(alias=>{
    const name=normalizeAtName(alias);return userName===name||userName.startsWith(`${name} `)||name.startsWith(`${userName} `)
  }))
}

export function RegionalVisitDashboard({clients,visits,plans,checks,user,period,onPeriod,onProfile,onSchedule,onRegister,onComplete,onAgenda}:{
  clients:Client[];visits:Visit[];plans:MonthlyPlan[];checks:RegionalChecklist[];user:CurrentUser;period:string;
  onPeriod:(period:string)=>void;onProfile:(client:Client)=>void;onSchedule:(client:Client)=>void;onRegister:(client:Client,scheduled?:Visit)=>void;onComplete:(visit:Visit)=>void;onAgenda:()=>void;
}) {
  const [adjustmentPrompt,setAdjustmentPrompt]=useState<string|null>(null)
  const assignments=plans.filter(plan=>plan.period.slice(0,7)===period&&belongsToUser(plan,user))
  const details=assignments.map(plan=>{
    const client=clients.find(item=>item.id===plan.client_id)
    const related=visits.filter(visit=>visit.clientId===plan.client_id&&visit.date.startsWith(period)&&(visit.representativeId===user.id||matchesPlan(visit,plan)))
    const realized=related.find(visit=>visit.status==='Realizada')
    const scheduled=related.find(visit=>['Programada','Reagendada','Atrasada'].includes(visit.status))
    const check=realized?checks.find(item=>item.visit_id===realized.id):undefined
    const billable=client?regionalForVisit(client.state,realized?.accountManager??user.fullName)?.billable!==false:true
    let bucket:Bucket='to-visit'
    if(check?.status==='Aprovada'&&billable&&check.payment_status==='Pago')bucket='done'
    else if(check?.status==='Aprovada')bucket='payment'
    else if(realized)bucket='validation'
    else if(scheduled)bucket='scheduled'
    return {plan,client,realized,scheduled,check,bucket}
  }).filter(item=>item.client)
  const groups:Record<Bucket,typeof details>={
    'to-visit':details.filter(item=>item.bucket==='to-visit'),scheduled:details.filter(item=>item.bucket==='scheduled'),validation:details.filter(item=>item.bucket==='validation'),payment:details.filter(item=>item.bucket==='payment'),done:details.filter(item=>item.bucket==='done'),
  }
  const nonBillable=REGIONALS.some(r=>!r.billable&&r.aliases.some(alias=>normalizeAtName(user.fullName).startsWith(normalizeAtName(alias))))
  const firstAdjustment=details.find(item=>item.check?.status==='Ajustar'&&item.realized)
  useEffect(()=>{if(firstAdjustment?.realized?.id)setAdjustmentPrompt(current=>current??firstAdjustment.realized!.id)},[firstAdjustment?.realized?.id])
  const cards:[Bucket,string,string,typeof MapPin][]=[
    ['to-visit','Visitas/Reuniões a Realizar','Planejamento do mês',MapPin],['scheduled','Visitas Agendadas','Abrir agenda',CalendarDays],['validation','Aguardando Validação','Enviadas à gestão',Clock3],['payment',nonBillable?'Visitas Validadas':'Pagamento Pendente',nonBillable?'Conferência':'Aguardando fechamento',nonBillable?CheckCircle2:WalletCards],['done',nonBillable?'Histórico Validado':'Pagamento Realizado','Consultar e exportar',CheckCircle2],
  ]
  return <section className="regional-mobile-dashboard">
    <header className="regional-mobile-header"><div><span className="eyebrow">MINHA CARTEIRA MENSAL</span><h1>Olá, {user.fullName.split(' ')[0]}</h1><p>Veja as prioridades, organize sua agenda e registre as visitas pelo celular.</p></div><label>Mês<input type="month" value={period} onInput={event=>onPeriod(event.currentTarget.value)}/></label></header>
    <div className="regional-dashboard-cards">{cards.map(([key,label,help,Icon])=><a href={`#regional-${key}`} onClick={key==='scheduled'?event=>{event.preventDefault();onAgenda()}:undefined} key={key}><Icon size={20}/><span>{label}</span><strong>{groups[key].length}</strong><small>{help}</small><ChevronRight size={17}/></a>)}</div>
    {cards.map(([key,label])=><section className="regional-assignment-section" id={`regional-${key}`} key={key}>
      <div className="regional-section-title"><div><span className="eyebrow">{label.toUpperCase()}</span><h2>{label}</h2></div><span className="count-badge">{groups[key].length}</span></div>
      {!groups[key].length&&<p className="regional-empty">Nenhum registro nesta etapa para o mês selecionado.</p>}
      {groups[key].map(({plan,client,realized,scheduled,check})=><article className="regional-assignment-card" key={plan.id??plan.client_id}>
        <div className="regional-assignment-top"><div><span className={`regional-priority ${plan.priority.toLowerCase()}`}>{plan.priority}</span><h3>{client!.siteName}</h3><p><MapPin size={13}/>{client!.state} · {client!.administrator}</p></div><span className="regional-date">{scheduled?'Agendada':'Competência'}<br/><b>{scheduled?scheduled.date.split('-').reverse().join('/'):period.split('-').reverse().join('/')}</b></span></div>
        <div className="regional-reasons">{plan.relationship_reason&&<span>Relacionamento</span>}{plan.ticket_volume_reason&&<span>Volume de chamados</span>}</div>
        <div className="regional-guidance"><b>Contexto da gestão</b><p>{plan.guidance?.trim()||'Sem orientação adicional registrada.'}</p></div>
        {check?.status==='Ajustar'&&<div className="regional-adjustment"><b>Ajuste solicitado pela gestão</b><p>{check.review_note}</p></div>}
        {scheduled&&<p className="regional-inline-info"><CalendarDays size={15}/><b>{scheduled.date.split('-').reverse().join('/')}</b> às {scheduled.time?.slice(0,5)||'—'} · {scheduled.receivedBy}</p>}
        {realized&&<p className="regional-inline-info"><FileText size={15}/>Realizada em {realized.date.split('-').reverse().join('/')} · {check?.status==='Aprovada'?'Validada':check?.status==='Pendente'?'Em análise':check?.status==='Ajustar'?'Ajuste necessário':'Complete e envie para validação'}</p>}
        <div className="regional-card-actions"><button className="secondary" onClick={()=>onProfile(client!)}>Perfil e chamados</button>{key==='to-visit'&&<><button className="primary" onClick={()=>onSchedule(client!)}>Agendar visita/reunião</button><button className="secondary" onClick={()=>onRegister(client!)}>Registrar já realizada</button></>}{key==='scheduled'&&scheduled&&<><button className="secondary" onClick={()=>downloadVisitCalendar(scheduled,client!.siteName)}><Download size={15}/> Minha agenda</button><button className="primary" onClick={()=>onRegister(client!,scheduled)}>Registrar visita</button></>}{key==='validation'&&realized&&check?.status!=='Pendente'&&<button className="primary" onClick={()=>onComplete(realized)}>{check?.status==='Ajustar'?'Corrigir e reenviar':'Completar e enviar'}</button>}</div>
      </article>)}
    </section>)}
    {adjustmentPrompt&&firstAdjustment?.realized?.id===adjustmentPrompt&&<div className="modal-backdrop"><section className="modal regional-modal regional-adjustment-popup" role="dialog" aria-modal="true" aria-labelledby="regional-adjustment-title"><AlertCircle size={30}/><span className="eyebrow">AJUSTE SOLICITADO</span><h2 id="regional-adjustment-title">Revise a visita de {firstAdjustment.client!.siteName}</h2><p>{firstAdjustment.check?.review_note}</p><div className="regional-actions"><button className="secondary" onClick={()=>setAdjustmentPrompt(null)}>Ver depois</button><button className="primary" onClick={()=>{setAdjustmentPrompt(null);onComplete(firstAdjustment.realized!)}}>Corrigir agora</button></div></section></div>}
  </section>
}
