import { addDays, dayKey, fromKey } from './dates';
import { parseQuestions } from './importer';
import { COURSE_COLORS, DEFAULT_SETTINGS, uid } from './store';
import type { AppState, Course, Question } from './types';

const DIGITAL = `Q: Which logic gate gives a HIGH output only when all its inputs are HIGH?
A) OR
B) AND
C) NAND
D) XOR
Answer: B
Explanation: AND outputs 1 only when every input is 1.
Topic: Logic gates

Q: What is the decimal value of the binary number 1011?
A) 9
B) 10
C) 11
D) 13
Answer: C
Explanation: 8 + 0 + 2 + 1 = 11.
Topic: Number systems

Q: Which gates are called universal gates?
A) AND and OR
B) NAND and NOR
C) XOR and XNOR
D) NOT and AND
Answer: B
Explanation: Any Boolean function can be built from NAND gates alone, or NOR gates alone.
Topic: Logic gates

Q: A flip-flop stores how many bits?
A) 1
B) 2
C) 4
D) 8
Answer: A
Topic: Sequential circuits

Q: Simplify the Boolean expression A + AB.
A) AB
B) B
C) A
D) A + B
Answer: C
Explanation: Absorption law: A + AB = A(1 + B) = A.
Topic: Boolean algebra

Q: How many select lines does an 8-to-1 multiplexer need?
A) 2
B) 3
C) 4
D) 8
Answer: B
Explanation: 2^3 = 8 inputs, so 3 select lines.
Topic: Combinational circuits

Q: State De Morgan's two theorems.
Answer: (A·B)' = A' + B', and (A + B)' = A'·B'.
Topic: Boolean algebra

Q: Explain the difference between a latch and a flip-flop.
Answer: A latch is level-triggered: its output follows the input while enable is active. A flip-flop is edge-triggered: it changes only on a clock edge.
Topic: Sequential circuits`;

const MICRO = `Q: Which register holds the address of the next instruction to execute?
A) Accumulator
B) Stack pointer
C) Program counter
D) Instruction register
Answer: C
Topic: CPU architecture

Q: How many address lines are needed to address 64 KB of memory?
A) 8
B) 16
C) 20
D) 32
Answer: B
Explanation: 2^16 = 65,536 bytes = 64 KB.
Topic: Memory interfacing

Q: What does an interrupt service routine end with on most microprocessors?
A) A return-from-interrupt instruction
B) A halt instruction
C) A jump to address 0
D) A no-operation instruction
Answer: A
Topic: Interrupts

Q: Which addressing mode is used in MOV A, #25H?
A) Direct
B) Register indirect
C) Immediate
D) Indexed
Answer: C
Explanation: The # sign means the value itself is in the instruction.
Topic: Instruction set

Q: Describe what happens when a microprocessor receives a hardware interrupt.
Answer: It finishes the current instruction, saves the program counter (and flags) on the stack, jumps to the interrupt service routine, runs it, then returns and restores the saved state.
Topic: Interrupts`;

function examIn(days: number, hour: number): string {
  const d = fromKey(addDays(dayKey(), days));
  d.setHours(hour, 0, 0, 0);
  return d.toISOString();
}

function topics(names: [string, 1 | 2 | 3][]) {
  return names.map(([name, confidence]) => ({ id: uid(), name, confidence }));
}

/** Two demo courses with real questions, so a new user can see how everything works. */
export function sampleState(name = ''): AppState {
  const courses: Course[] = [
    {
      id: uid(), code: 'CPE 501', title: 'Digital Systems Design', examAt: examIn(12, 9), venue: 'Main hall', difficulty: 2, color: COURSE_COLORS[0],
      topics: topics([['Number systems', 3], ['Boolean algebra', 2], ['Logic gates', 2], ['Combinational circuits', 1], ['Sequential circuits', 1]]),
    },
    {
      id: uid(), code: 'CPE 503', title: 'Microprocessor Systems', examAt: examIn(19, 13), venue: 'LT 2', difficulty: 3, color: COURSE_COLORS[1],
      topics: topics([['CPU architecture', 2], ['Instruction set', 1], ['Memory interfacing', 1], ['Interrupts', 1]]),
    },
  ];
  const questions: Question[] = [
    ...parseQuestions(DIGITAL).questions.map(q => ({ ...q, id: uid(), courseId: courses[0].id })),
    ...parseQuestions(MICRO).questions.map(q => ({ ...q, id: uid(), courseId: courses[1].id })),
  ];
  return { courses, questions, cards: {}, sessions: [], mocksDone: [], attempts: [], settings: { ...DEFAULT_SETTINGS, name } };
}
