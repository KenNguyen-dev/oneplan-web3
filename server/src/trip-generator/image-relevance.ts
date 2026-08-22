// Relevance gate for scraped photos. A photo attached to a plan item is a
// promise to the traveler ("this is what the place looks like"), so a wrong
// photo is worse than no photo at all. Every candidate must pass two hard
// gates before it is downloaded:
//
//   1. PLACE  - the title names the venue, or at least the destination
//   2. ACTIVITY - the title is consistent with what the traveler DOES there
//
// Real failures this exists to stop (Cao Bang listing, 2026-07):
//   "Bua toi ... Nha hang Minh Nguyet"  -> a Ban Gioc waterfall panorama and
//       a hotel lobby, both of which matched only on the city token.
//   "Ca phe chia tay tai La-Rose"       -> bowls of pho and banh cuon.
//   "Pho chua Dung Trang"               -> stainless-steel buffet equipment,
//       matched purely on the common syllable "trang".
// Hence: destination alone never proves a photo, and a venue must be matched
// on TWO distinctive tokens when it has them.

import { ActivityClass, UNIVERSAL_FORBID } from './activity-hints';
import { normalize, tokenize } from './place-lookup';

export type ImageVerdict = 'pass' | 'unverified' | 'fail';

export interface ImageGate {
  // Distinctive tokens of the venue name ("minh", "nguyet"), already stripped
  // of generic venue words by imageRelevanceTokens().
  venueTokens: string[];
  // Distinctive tokens of the destination ("cao", "bang").
  destTokens: string[];
  // The destination as written ("Cao Bằng, Cao Bằng, Vietnam"), used to tell
  // "another city is named here" from "the destination is named here".
  destination: string;
  // Null for items whose activity we could not classify (pure transit).
  activity: ActivityClass | null;
}

export interface ImageReview {
  verdict: ImageVerdict;
  // Short machine-readable reason, mirrors the reviewer playbook's
  // "FAIL(gate: why)" verdict format. Used in logs.
  reason: string;
}

// Matches a vocabulary entry against the folded title: single words match a
// whole token, multi-word entries match as a phrase.
function hits(words: Set<string>, padded: string, vocab: readonly string[]) {
  return vocab.find((v) =>
    v.includes(' ') ? padded.includes(` ${v} `) : words.has(v),
  );
}

// How many name tokens the title must carry. One is enough only when the name
// HAS a single distinctive token; otherwise a lone common syllable is not
// evidence: "trang" also means "page", and a cafe in "Hữu Bằng" or a "CAO
// Coffee" in Saigon are not photos of Cao Bang.
function tokensNeeded(tokens: string[]): number {
  return Math.min(2, tokens.length);
}

function countHits(tokens: string[], words: Set<string>): number {
  return new Set(tokens.filter((t) => words.has(t))).size;
}

// Venue names repeat across provinces ("Nhà hàng Minh Nguyệt" exists in both
// Cao Bang and Thai Nguyen), so a name match is not proof of location. When a
// title names a DIFFERENT city than the destination, the photo is that other
// city's. ASCII-folded; single syllables that double as ordinary Vietnamese
// words ("vinh", "hoa", "bac") are left out on purpose.
const CITY_NAMES: readonly string[] = [
  'ha noi',
  'hanoi',
  'ho chi minh',
  'saigon',
  'sai gon',
  'da nang',
  'danang',
  'hai phong',
  'can tho',
  'hue',
  'da lat',
  'dalat',
  'nha trang',
  'vung tau',
  'phu quoc',
  'ha long',
  'sa pa',
  'sapa',
  'hoi an',
  'quy nhon',
  'phan thiet',
  'mui ne',
  'ninh binh',
  'thai nguyen',
  'bac ninh',
  'bac giang',
  'quang ninh',
  'lang son',
  'cao bang',
  'ha giang',
  'tuyen quang',
  'lao cai',
  'yen bai',
  'phu tho',
  'son la',
  'dien bien',
  'lai chau',
  'hoa binh',
  'thanh hoa',
  'nghe an',
  'ha tinh',
  'quang binh',
  'quang tri',
  'quang nam',
  'quang ngai',
  'binh dinh',
  'phu yen',
  'khanh hoa',
  'ninh thuan',
  'binh thuan',
  'kon tum',
  'gia lai',
  'dak lak',
  'dak nong',
  'lam dong',
  'binh phuoc',
  'tay ninh',
  'binh duong',
  'dong nai',
  'long an',
  'tien giang',
  'ben tre',
  'tra vinh',
  'vinh long',
  'dong thap',
  'an giang',
  'kien giang',
  'hau giang',
  'soc trang',
  'bac lieu',
  'ca mau',
  'bangkok',
  'singapore',
  'kuala lumpur',
  'chiang mai',
  'phuket',
  'hong kong',
  'taipei',
  'tokyo',
  'osaka',
  'kyoto',
  'seoul',
  'bali',
];

// The name of another city found in the title, or undefined when the title
// only mentions the destination (or no city at all). Matched against the whole
// destination string, not its filtered tokens, so "Hồ Chí Minh" is not read as
// a conflict for a Ho Chi Minh City trip.
function conflictingCity(
  words: Set<string>,
  padded: string,
  destPadded: string,
): string | undefined {
  return CITY_NAMES.find(
    (city) =>
      (city.includes(' ') ? padded.includes(` ${city} `) : words.has(city)) &&
      !destPadded.includes(city),
  );
}

// Review one search result title against the gate. `unverified` means "no
// usable title" (Bing results often carry only a filename): such a photo is
// never accepted on the title alone, but a vision review may still clear it.
export function reviewImageTitle(title: string, gate: ImageGate): ImageReview {
  const folded = normalize(title);
  const words = new Set(tokenize(title));
  if (!folded || words.size === 0) {
    return { verdict: 'unverified', reason: 'no title to verify' };
  }
  const padded = ` ${folded} `;

  const junk = hits(words, padded, UNIVERSAL_FORBID);
  if (junk) return { verdict: 'fail', reason: `junk/wrong medium: "${junk}"` };

  if (gate.activity) {
    const bad = hits(words, padded, gate.activity.forbid);
    if (bad) {
      return {
        verdict: 'fail',
        reason: `activity mismatch (${gate.activity.id}): "${bad}"`,
      };
    }
  }

  const elsewhere = conflictingCity(
    words,
    padded,
    ` ${normalize(gate.destination)} `,
  );
  if (elsewhere) {
    return { verdict: 'fail', reason: `photo of another city: "${elsewhere}"` };
  }

  const venueHits = countHits(gate.venueTokens, words);
  const venueMatch =
    gate.venueTokens.length > 0 && venueHits >= tokensNeeded(gate.venueTokens);
  const destMatch =
    gate.destTokens.length > 0 &&
    countHits(gate.destTokens, words) >= tokensNeeded(gate.destTokens);
  const activityMatch = gate.activity
    ? Boolean(hits(words, padded, gate.activity.require))
    : false;

  // Two distinctive venue tokens is strong evidence on its own.
  if (venueHits >= 2) return { verdict: 'pass', reason: 'venue name in title' };
  // A single-token venue is weaker: it needs the city or the activity too.
  if (venueMatch && (destMatch || activityMatch)) {
    return { verdict: 'pass', reason: 'venue + context' };
  }
  // No venue: the photo must prove BOTH where and what. This is the rule that
  // stops a city landscape from being served as dinner.
  if (destMatch && activityMatch) {
    return { verdict: 'pass', reason: 'destination + activity' };
  }
  if (!gate.activity && destMatch) {
    return {
      verdict: 'unverified',
      reason: 'destination only, activity unknown',
    };
  }
  return {
    verdict: 'fail',
    reason: destMatch
      ? `in destination but activity not shown (${gate.activity?.id ?? 'unknown'})`
      : 'neither venue nor destination in title',
  };
}
