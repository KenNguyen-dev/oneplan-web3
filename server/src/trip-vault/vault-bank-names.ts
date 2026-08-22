/**
 * NAPAS bank identification numbers to display names.
 *
 * A partial list, covering the banks a Vietnamese merchant QR is most likely to
 * carry. An unknown BIN falls back to the number itself rather than to an empty
 * string, so a receipt never hides which bank was paid.
 *
 * MoMo (and ZaloPay) personal receive QRs are VietQR that settle into a
 * BVBank virtual account — BIN `970454`, account often like `99MM…`.
 */
const BANK_NAMES: Record<string, string> = {
  '970400': 'SaigonBank',
  '970403': 'Sacombank',
  '970405': 'Agribank',
  '970406': 'DongA Bank',
  '970407': 'Techcombank',
  '970408': 'GPBank',
  '970409': 'BacA Bank',
  '970410': 'Standard Chartered',
  '970412': 'PVcomBank',
  '970414': 'Oceanbank',
  '970415': 'VietinBank',
  '970416': 'ACB',
  '970418': 'BIDV',
  '970419': 'NCB',
  '970422': 'MB Bank',
  '970423': 'TPBank',
  '970424': 'Shinhan Bank',
  '970425': 'ABBANK',
  '970426': 'MSB',
  '970427': 'VietABank',
  '970428': 'NamA Bank',
  '970429': 'SCB',
  '970430': 'PGBank',
  '970431': 'Eximbank',
  '970432': 'VPBank',
  '970433': 'VietBank',
  '970436': 'Vietcombank',
  '970437': 'HDBank',
  '970438': 'BaoViet Bank',
  '970439': 'PublicBank',
  '970440': 'SeABank',
  '970441': 'VIB',
  '970442': 'HongLeong Bank',
  '970443': 'SHB',
  '970448': 'OCB',
  '970449': 'LienVietPostBank',
  '970452': 'KienLongBank',
  // BVBank / Viet Capital — MoMo & ZaloPay wallet VietQR use this BIN.
  '970454': 'BVBank',
  '970455': 'IBK',
  '970457': 'Woori Bank',
  '970458': 'United Overseas Bank',
  '970460': 'VietinBank Securities',
};

/** BINs the mock payout (and UI bank labels) treat as valid NAPAS banks. */
export const NAPAS_BANK_BINS = new Set(Object.keys(BANK_NAMES));

export function bankNameFor(bankBin: string | null): string {
  if (!bankBin) {
    return '';
  }
  return BANK_NAMES[bankBin] ?? bankBin;
}
