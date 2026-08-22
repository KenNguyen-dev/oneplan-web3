/**
 * Minimal EMVCo QR decoder for VietQR payloads.
 *
 * The format is a flat sequence of tag-length-value triples: a two digit tag, a
 * two digit decimal length, then that many characters of value. Nested fields
 * (38, 62) hold another TLV sequence as their value.
 *
 * Only what a payment needs is extracted: the bank BIN and account number, plus
 * the amount and description when the code carries them. Most merchant codes are
 * static and omit the amount, which is why the app asks the user to type it.
 */

export class VietQrDecodeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'VietQrDecodeError';
  }
}

export interface VietQrPayload {
  bankBin: string;
  accountNumber: string;
  amountVnd: bigint | null;
  description: string | null;
}

const TAG_MERCHANT_ACCOUNT = '38';
const TAG_CURRENCY = '53';
const TAG_AMOUNT = '54';
const TAG_ADDITIONAL = '62';
const SUB_TAG_BANK_BIN = '00';
const SUB_TAG_ACCOUNT = '01';
const SUB_TAG_BENEFICIARY = '01';
const SUB_TAG_DESCRIPTION = '08';
const CURRENCY_VND = '704';

function parseTlv(input: string): Map<string, string> {
  const out = new Map<string, string>();
  let i = 0;

  while (i < input.length) {
    if (i + 4 > input.length) {
      throw new VietQrDecodeError(
        'truncated payload: incomplete tag or length',
      );
    }
    const tag = input.slice(i, i + 2);
    const rawLength = input.slice(i + 2, i + 4);
    if (!/^\d{2}$/.test(rawLength)) {
      throw new VietQrDecodeError(
        `invalid length "${rawLength}" for tag ${tag}`,
      );
    }
    const length = Number(rawLength);
    const start = i + 4;
    const end = start + length;
    if (end > input.length) {
      throw new VietQrDecodeError(`truncated value for tag ${tag}`);
    }
    out.set(tag, input.slice(start, end));
    i = end;
  }

  return out;
}

export function decodeVietQr(payload: string): VietQrPayload {
  if (!payload) {
    throw new VietQrDecodeError('empty payload');
  }

  const root = parseTlv(payload);

  const currency = root.get(TAG_CURRENCY);
  if (currency && currency !== CURRENCY_VND) {
    throw new VietQrDecodeError(
      `unsupported currency ${currency}, expected ${CURRENCY_VND} (VND)`,
    );
  }

  const merchant = root.get(TAG_MERCHANT_ACCOUNT);
  if (!merchant) {
    throw new VietQrDecodeError(
      'missing merchant account information (tag 38)',
    );
  }

  const merchantFields = parseTlv(merchant);
  const beneficiary = merchantFields.get(SUB_TAG_BENEFICIARY);
  if (!beneficiary) {
    throw new VietQrDecodeError('missing beneficiary organisation (tag 38-01)');
  }

  const beneficiaryFields = parseTlv(beneficiary);
  const bankBin = beneficiaryFields.get(SUB_TAG_BANK_BIN);
  const accountNumber = beneficiaryFields.get(SUB_TAG_ACCOUNT);
  if (!bankBin || !accountNumber) {
    throw new VietQrDecodeError('missing bank bin or account number');
  }

  const rawAmount = root.get(TAG_AMOUNT);
  let amountVnd: bigint | null = null;
  if (rawAmount) {
    if (!/^\d+(\.\d+)?$/.test(rawAmount)) {
      throw new VietQrDecodeError(`invalid amount "${rawAmount}"`);
    }
    // VND has no minor units; a trailing ".00" is tolerated and truncated.
    amountVnd = BigInt(rawAmount.split('.')[0]);
  }

  let description: string | null = null;
  const additional = root.get(TAG_ADDITIONAL);
  if (additional) {
    description = parseTlv(additional).get(SUB_TAG_DESCRIPTION) ?? null;
  }

  return { bankBin, accountNumber, amountVnd, description };
}
