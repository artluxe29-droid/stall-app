import type { Question } from './types';

export type DraftQuestion =
  | Omit<Extract<Question, { kind: 'mcq' }>, 'id' | 'courseId'>
  | Omit<Extract<Question, { kind: 'theory' }>, 'id' | 'courseId'>;

export interface ImportResult {
  questions: DraftQuestion[];
  errors: string[];
}

export const IMPORT_EXAMPLE = `Q: Which logic gate gives a HIGH output only when all inputs are HIGH?
A) OR
B) AND
C) NOR
D) XOR
Answer: B
Explanation: An AND gate outputs 1 only when every input is 1.
Topic: Logic gates
Year: 2023

Q: State Kirchhoff's current law.
Answer: The sum of currents entering a node equals the sum of currents leaving it.
Topic: Circuit laws`;

const Q_MARK = /^\s*Q(?:uestion)?\s*\d*\s*[:.)-]\s*/i;
const NUM_MARK = /^\s*\d{1,3}\s*[.)]\s+/;
const OPTION = /^\s*\(?([A-Ea-e])\s*[).:]\s+(.*)$/;
const FIELD = /^\s*(Answer|Ans|Explanation|Exp|Topic|Year)\s*[:.-]\s*(.*)$/i;

/**
 * Parses pasted past questions. Each question starts with "Q:" (or "1." when no
 * "Q:" markers are used). Lines "A) ..." to "E) ..." make it multiple choice;
 * without options it is a theory question whose "Answer:" is the model answer.
 */
export function parseQuestions(text: string): ImportResult {
  const lines = text.replace(/\r\n?/g, '\n').split('\n');
  const useQ = lines.some(l => Q_MARK.test(l));
  const marker = useQ ? Q_MARK : NUM_MARK;

  const blocks: string[][] = [];
  for (const line of lines) {
    if (marker.test(line)) blocks.push([line.replace(marker, '')]);
    else if (blocks.length) blocks[blocks.length - 1].push(line);
  }

  const questions: DraftQuestion[] = [];
  const errors: string[] = [];

  blocks.forEach((block, i) => {
    const n = i + 1;
    let prompt = '';
    const options: string[] = [];
    const fields: Record<string, string> = {};
    let current: 'prompt' | 'option' | string = 'prompt';

    for (const raw of block) {
      const line = raw.trimEnd();
      const field = line.match(FIELD);
      const option = current !== 'answer' && current !== 'explanation' ? line.match(OPTION) : null;
      if (field) {
        const name = field[1].toLowerCase();
        current = name === 'ans' ? 'answer' : name === 'exp' ? 'explanation' : name;
        fields[current] = field[2].trim();
      } else if (option && (current === 'prompt' || current === 'option')) {
        options.push(option[2].trim());
        current = 'option';
      } else if (line.trim()) {
        if (current === 'prompt') prompt = prompt ? `${prompt}\n${line.trim()}` : line.trim();
        else if (current === 'option') options[options.length - 1] += ` ${line.trim()}`;
        else fields[current] = fields[current] ? `${fields[current]}\n${line.trim()}` : line.trim();
      }
    }

    prompt = prompt.trim();
    if (!prompt) {
      errors.push(`Question ${n}: the question text is missing.`);
      return;
    }
    const extra = {
      ...(fields.topic ? { topic: fields.topic } : {}),
      ...(fields.year ? { year: fields.year } : {}),
    };

    if (options.length) {
      if (options.length < 2) {
        errors.push(`Question ${n}: a multiple-choice question needs at least 2 options.`);
        return;
      }
      const ans = (fields.answer ?? '').trim();
      let answer = -1;
      const letter = ans.match(/^\(?([A-Ea-e])\)?(?:[).:\s]|$)/);
      if (letter) answer = letter[1].toUpperCase().charCodeAt(0) - 65;
      else if (ans) answer = options.findIndex(o => o.toLowerCase() === ans.toLowerCase());
      if (answer < 0 || answer >= options.length) {
        errors.push(`Question ${n}: add "Answer: A" (or the letter of the correct option).`);
        return;
      }
      questions.push({ kind: 'mcq', prompt, options, answer, ...(fields.explanation ? { explanation: fields.explanation } : {}), ...extra });
    } else {
      if (!fields.answer) {
        errors.push(`Question ${n}: add "Answer:" with a model answer.`);
        return;
      }
      questions.push({ kind: 'theory', prompt, modelAnswer: fields.answer, ...extra });
    }
  });

  if (!blocks.length && text.trim()) errors.push('No questions found. Start each question with "Q:".');
  return { questions, errors };
}
