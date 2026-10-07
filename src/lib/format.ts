const partnershipMonths = ['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez']

export function formatPartnershipStart(value?: string | null) {
  const match = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(value?.trim() ?? '')
  if (!match) return 'Não informado'
  const month = Number(match[2])
  if (month < 1 || month > 12) return 'Não informado'
  return `${partnershipMonths[month - 1]}/${match[3].slice(-2)}`
}
