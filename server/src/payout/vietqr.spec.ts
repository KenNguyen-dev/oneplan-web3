import { decodeVietQr, VietQrDecodeError } from './vietqr';

/**
 * Builds an EMVCo TLV string. Each field is tag (2 digits), length (2 digits),
 * then the value. The CRC field 63 is appended last and is not validated by the
 * decoder, so a placeholder is fine here.
 */
function tlv(tag: string, value: string): string {
  return tag + String(value.length).padStart(2, '0') + value;
}

function buildQr(opts: {
  bankBin: string;
  account: string;
  amount?: string;
  description?: string;
}): string {
  const merchant =
    tlv('00', 'A000000727') +
    tlv('01', tlv('00', opts.bankBin) + tlv('01', opts.account)) +
    tlv('02', 'QRIBFTTA');
  let body =
    tlv('00', '01') +
    tlv('01', opts.amount ? '12' : '11') +
    tlv('38', merchant) +
    tlv('53', '704');
  if (opts.amount) body += tlv('54', opts.amount);
  body += tlv('58', 'VN');
  if (opts.description) body += tlv('62', tlv('08', opts.description));
  return body + tlv('63', 'ABCD');
}

describe('decodeVietQr', () => {
  it('extracts the bank bin and account number from a static code', () => {
    const qr = buildQr({ bankBin: '970412', account: '109000636588' });
    const decoded = decodeVietQr(qr);

    expect(decoded.bankBin).toBe('970412');
    expect(decoded.accountNumber).toBe('109000636588');
    expect(decoded.amountVnd).toBeNull();
  });

  it('extracts the amount from a dynamic code', () => {
    const qr = buildQr({
      bankBin: '970407',
      account: '19036045678901',
      amount: '200000',
    });
    const decoded = decodeVietQr(qr);

    expect(decoded.bankBin).toBe('970407');
    expect(decoded.amountVnd).toBe(200000n);
  });

  it('tolerates a trailing decimal on the amount', () => {
    const qr = buildQr({
      bankBin: '970407',
      account: '1903604',
      amount: '200000.00',
    });
    expect(decodeVietQr(qr).amountVnd).toBe(200000n);
  });

  it('extracts the description when present', () => {
    const qr = buildQr({
      bankBin: '970436',
      account: '1234567890',
      description: 'Chuyen tien',
    });
    expect(decodeVietQr(qr).description).toBe('Chuyen tien');
  });

  it('rejects a payload with no merchant account field', () => {
    const qr = tlv('00', '01') + tlv('53', '704') + tlv('63', 'ABCD');
    expect(() => decodeVietQr(qr)).toThrow(VietQrDecodeError);
  });

  it('rejects a currency other than VND', () => {
    const qr = buildQr({ bankBin: '970412', account: '1' }).replace(
      tlv('53', '704'),
      tlv('53', '840'),
    );
    expect(() => decodeVietQr(qr)).toThrow(/currency/i);
  });

  it('rejects a truncated payload', () => {
    expect(() => decodeVietQr('0002015802')).toThrow(VietQrDecodeError);
  });

  it('rejects an empty payload', () => {
    expect(() => decodeVietQr('')).toThrow(VietQrDecodeError);
  });

  it('rejects a length field that is not two digits', () => {
    expect(() => decodeVietQr('00XX01')).toThrow(VietQrDecodeError);
  });
});
