# Contracts, Not Skills: The Right Primitive for AI Systems

## The Problem

The AI ecosystem is building skills — step-by-step instructions that tell models how to accomplish goals. Skills seem like a great idea. They work today. They're the rage.

But skills are written based on AI's current weaknesses. They compensate for what the model can't figure out on its own.

Go back two years. Imagine writing a skills file for GPT-3. How verbose would it need to be? Extremely verbose. Because those systems had poor reasoning. You'd spell out every step, every edge case, every format detail.

Now look at today's models. They need less hand-holding. They can reason about multi-step problems. They infer format from examples. The skills you wrote for GPT-3 are now dead weight.

Now look forward two years. The skills you write today will be dead weight too.

**Skills are technical debt that accrues as models improve.** Every step-by-step instruction you write is a bet that future models will be as limited as today's. That bet has never paid off.

## What Survives

Contracts.

A contract defines:
- **What we want** — the end state, described as a schema
- **What's allowed** — the constraints
- **What's not allowed** — the guardrails

A contract does not define:
- How to get there
- What order to do things in
- What tools to use
- What to think about at each step

A contract is extremely terse compared to a skill. A contract for "improve a software project" is:

```json
{
  "goal": "Leave the project measurably better than you found it",
  "output": "improvement-snapshot.schema.json",
  "constraints": [
    "Every score must cite specific evidence from the codebase",
    "Fix the highest-impact gap, not the easiest",
    "Never violate the project's own guardrails",
    "Record every run — the next agent depends on it"
  ]
}
```

The equivalent skill is 150 lines of "Step 1: Read CLAUDE.md. Step 2: Check the directory structure. Step 3: Score using this rubric with these calibration examples..."

The contract says *what*. The skill says *how*. Models get better at *how* every six months. *What* doesn't change.

## The Chess Analogy

Richard Sutton's bitter lesson: general methods that leverage computation always beat hand-crafted human knowledge as compute scales.

We teach a computer to play chess by giving it:
1. The rules of chess (a contract)
2. A goal (win)

We don't give it:
1. Step 1: Control the center
2. Step 2: Develop your knights before bishops
3. Step 3: Castle early
4. Step 4: ...

That's a skill. It works for beginners. It fails at grandmaster level. The system that learned to play chess without human strategy knowledge (AlphaZero) destroyed the system that was built on decades of human chess expertise (Stockfish).

Skills are chess strategy books. Contracts are the rules of chess. One decays. The other is permanent.

## What This Means for Building AI Systems

### Skills-First (how most teams build today)

```
skills/
  improve-project.md        ← 150 lines of step-by-step
  review-code.md            ← 200 lines of what to check
  deploy-service.md         ← 100 lines of deployment steps
```

Every model upgrade makes these partially obsolete. You rewrite them. The rewrite introduces new assumptions about the model's weaknesses. Those assumptions become obsolete at the next upgrade. Repeat forever.

### Contracts-First (what survives)

```
contracts/
  improvement-snapshot.schema.json    ← what "better" looks like
  deployment-record.schema.json       ← what "deployed" looks like
  code-review.schema.json             ← what "reviewed" looks like
```

The model changes. The contract doesn't. A better model produces a better improvement snapshot — more insightful scores, sharper fixes — but the snapshot still conforms to the same schema. The contract is the stable interface between human intent and AI capability.

### The Transition

You don't have to abandon skills today. Current models still benefit from guidance. The shift is:

1. **Define the contract first.** What does the output look like? What's a valid result? Write the JSON Schema.
2. **Write the skill second.** If the model can't meet the contract from the schema alone, add a skill as scaffolding.
3. **Test without the skill periodically.** Give the model just the contract. If the output conforms, the skill is no longer needed.
4. **Let skills decay.** Don't maintain them. Don't version them. They're temporary bridges.

The contracts directory is permanent infrastructure. The skills directory is a construction site that eventually gets torn down.

## In Practice: Eidos Assistant

Eidos Assistant is an open-source Mac app that captures voice notes. It has 5 JSON Schema contracts defining every data boundary:

- **Recording bucket** — what a voice recording looks like on disk
- **Manifest entry** — how recordings are tracked for discovery
- **Daemon protocol** — how the app talks to the classification daemon
- **Adapter manifest** — how the app registers itself with the search engine
- **Performance metric** — how transcription speed is tracked

Any AI model — current or future — can participate in this system by reading the contracts. The contracts tell it what data to produce. The model figures out how.

The app also has skills (step-by-step instructions for recording, transcribing, classifying). Those skills work today. They'll be unnecessary when models can infer the workflow from the contracts alone. The contracts will still be there.

## The Principle

**Contracts are the primitive that survives AGI.** Because contracts define what we want, not how to deliver it. A contract is a goal with structure. As long as humans have goals, contracts have value. As long as AI improves at reasoning, skills lose value.

Build contracts. Let skills decay.

---

*Published by [Eidos AGI](https://eidosagi.com). Source: [eidos-agi/eidos-assistant](https://github.com/eidos-agi/eidos-assistant).*
