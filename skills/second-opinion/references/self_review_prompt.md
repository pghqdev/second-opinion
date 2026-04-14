# Self-review prompt (fallback when no external CLI is available)

Use this prompt when `run_reviewer.sh` exits with code 10 (no external reviewer CLI found). You — the subagent — will perform the review yourself using your own model. This is a weaker "second opinion" than a different-model-family review, but a structured adversarial self-critique still catches real problems that a cooperative author misses.

Load a **fresh frame** before critiquing. You have been involved in producing or discussing this plan earlier in the conversation context; that priming biases you toward agreement. Actively reset:

- Read the plan as if a stranger handed it to you for review.
- Assume the plan is flawed until proven otherwise.
- Praise is only permitted for parts you would keep unchanged if you rewrote the plan from scratch. No "this section is good" filler.
- If you catch yourself writing "probably fine" or "should work" — that's the bias talking. Replace with a concrete failure mode or delete the sentence.

## The review

Apply these lenses to the plan, hardest first:

1. **Correctness** — which step silently assumes state, ordering, or tool behavior that may not hold? Cite the specific step.
2. **Reversibility** — what happens if a step half-succeeds? Which actions are irreversible (schema change, force-push, data deletion, third-party write) and what is the recovery path if they go wrong?
3. **Simplicity** — is there an obviously simpler approach that achieves the same goal? Is any abstraction, indirection, or ceremony doing work that the direct approach wouldn't?
4. **Hidden dependencies** — what must be true about the environment, credentials, existing code, or external services for this plan to succeed? Which of those are unstated?
5. **Blast radius** — what else breaks if this plan is wrong? Who is affected beyond the immediate change?

## Output

Respond with ONLY a single JSON object matching the schema at `assets/response_schema.json`. No preamble, no code fences, no trailing text.

Fields:
- `fatal_flaws`: array of strings, each tied to a concrete step or claim in the plan.
- `hidden_assumptions`: array of silent preconditions.
- `simpler_alternative`: string describing a materially different approach, or `null` if the plan is already minimal.
- `points_of_agreement`: array, 1–3 items, each a part of the plan you would keep unchanged. Empty array if nothing meets that bar — do NOT pad.
- `verdict`: `"SHIP"` / `"REVISE"` / `"RECONSIDER"`.
- `verdict_reason`: one sentence, no hedging.

Note in your returned summary to the dispatcher that this was a **self-review** (same model family as the main agent), not an external second opinion. The dispatcher should surface this caveat to the user so they weigh the verdict accordingly.

---

PLAN FOLLOWS:
