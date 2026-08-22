import {
  ValidationArguments,
  ValidationOptions,
  ValidatorConstraint,
  ValidatorConstraintInterface,
  registerDecorator,
} from 'class-validator';

const DEFAULT_PROFANE_TERMS = [
  'ass',
  'bastard',
  'bitch',
  'crap',
  'damn',
  'dick',
  'fuck',
  'fucking',
  'motherfucker',
  'piss',
  'shit',
] as const;

const profanityList = new Set(
  DEFAULT_PROFANE_TERMS.map((term) => term.toLowerCase()),
);
const matchCache = new WeakMap<object, Map<string, string[]>>();

function getCachedMatches(
  object: object,
  property: string,
): string[] | undefined {
  return matchCache.get(object)?.get(property);
}

function setCachedMatches(
  object: object,
  property: string,
  matches: string[],
): void {
  const current = matchCache.get(object) ?? new Map<string, string[]>();
  current.set(property, matches);
  matchCache.set(object, current);
}

function clearCachedMatches(object: object, property: string): void {
  const current = matchCache.get(object);
  if (!current) return;
  current.delete(property);
  if (current.size === 0) {
    matchCache.delete(object);
  }
}

function escapeForRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export function extractProfaneTerms(value: string): string[] {
  if (!value) return [];

  const lowercasedMatches = new Set<string>();

  for (const candidate of profanityList) {
    const escaped = escapeForRegex(candidate);
    const regex = new RegExp(`\\b${escaped}\\b`, 'i');
    if (regex.test(value)) {
      lowercasedMatches.add(candidate.toLowerCase());
    }
  }

  return [...lowercasedMatches].sort();
}

@ValidatorConstraint({ name: 'NoProfanity', async: false })
export class NoProfanityConstraint implements ValidatorConstraintInterface {
  validate(value: unknown, args: ValidationArguments): boolean {
    if (value === undefined || value === null) return true;
    if (typeof value !== 'string') return true;
    if (value.trim().length === 0) return true;

    const matches = extractProfaneTerms(value);
    setCachedMatches(args.object, args.property, matches);
    return matches.length === 0;
  }

  defaultMessage(args: ValidationArguments): string {
    const matches = getCachedMatches(args.object, args.property) ?? [];
    clearCachedMatches(args.object, args.property);

    if (matches.length === 0) {
      return `${args.property} contains profanity and is not allowed`;
    }

    return `${args.property} contains profanity and is not allowed. Matched terms: ${matches.join(', ')}`;
  }
}

export function NoProfanity(
  validationOptions?: ValidationOptions,
): PropertyDecorator {
  return (object: object, propertyName: string | symbol) => {
    registerDecorator({
      target: object.constructor,
      propertyName: propertyName.toString(),
      options: validationOptions,
      validator: NoProfanityConstraint,
    });
  };
}
