declare module 'bad-words' {
  interface FilterOptions {
    emptyList?: boolean;
    list?: string[];
    exclude?: string[];
    placeHolder?: string;
    regex?: RegExp;
    replaceRegex?: RegExp;
    splitRegex?: RegExp;
  }

  export default class Filter {
    list: string[];
    exclude: string[];
    placeHolder: string;
    regex: RegExp;
    replaceRegex: RegExp;
    splitRegex: RegExp;

    constructor(options?: FilterOptions);
    isProfane(input: string): boolean;
    replaceWord(input: string): string;
    clean(input: string): string;
    addWords(...words: string[]): void;
    removeWords(...words: string[]): void;
  }
}
