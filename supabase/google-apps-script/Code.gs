const DEFAULT_TAB = 'Perfil do Cliente';

function json(data) {
  return ContentService.createTextOutput(JSON.stringify(data)).setMimeType(ContentService.MimeType.JSON);
}

function doPost(e) {
  try {
    const payload = JSON.parse((e.postData && e.postData.contents) || '{}');
    if (payload.secret !== SYNC_SECRET) throw new Error('Não autorizado.');
    const file = SpreadsheetApp.openById('1W-Eoe8qpKlKoRJGkZ7Pb9G-hiyXbf-kMNpWcWvNcaWQ');
    const sheet = file.getSheetByName(payload.sheetName || DEFAULT_TAB);
    if (!sheet) throw new Error('Aba não encontrada.');

    if (payload.action === 'syncClient') {
      const row = Number(payload.row);
      if (!Number.isInteger(row) || row < 2) throw new Error('Linha inválida.');
      sheet.getRange(row, 25, 1, 4).setValues([[
        payload.name || '', payload.role || '', payload.phone || '', payload.email || ''
      ]]);
      sheet.getRange(row, 30).setValue(payload.permanentId || '');
      sheet.getRange(row, 15).setValue(payload.relationship || '');
      sheet.getRange(row, 22).setValue(payload.financial || '');
      sheet.getRange(row, 24).setValue(payload.training || '');
      sheet.getRange(row, 14).setValue(payload.manager || '');
      sheet.getRange(row, 16).setValue(payload.fleet || '');
      sheet.getRange(row, 23).setValue(payload.lastContact || '');
      sheet.getRange(1, 30).setValue('ID Interno');
      return json({ok: true});
    }

    if (payload.action === 'pullSheet') {
      const last = sheet.getLastRow();
      const values = last < 2 ? [] : sheet.getRange(2, 1, last - 1, 30).getDisplayValues().map(function(row) {
        return [row[24], row[25], row[26], row[27], row[29], row[14], row[21], row[23], row[13], row[15], row[22]];
      });
      return json({ok: true, values: values});
    }

    if (payload.action === 'backfillIds') {
      let updated = 0;
      (payload.clients || []).forEach(function(client) {
        const target = file.getSheetByName(client.sheetName || DEFAULT_TAB);
        const row = Number(client.row);
        if (target && Number.isInteger(row) && row >= 2) {
          target.getRange(1, 30).setValue('ID Interno');
          target.getRange(row, 30).setValue(client.permanentId);
          updated++;
        }
      });
      return json({ok: true, updated: updated});
    }

    throw new Error('Ação inválida.');
  } catch (error) {
    return json({ok: false, error: error.message});
  }
}
