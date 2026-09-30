# Tars hard multi-step benchmark

480 spoken commands that each ask for 2–4 things in one breath, across different
parts of an assistant, labeled with their steps and skills (catalog:
`catalogs/example_catalog.json`).

They were written to be hard to split: missing joiners ("open claude move it to the
left"), "and go" / "to" used as "and", later steps referring back ("move it", "that
song"), titles and queries containing command words ("play Stop Making Sense",
"search how to close a tab"), questions mixed with actions, and three speaking styles
(formal, gamer, non-technical) that were **kept out of training entirely**.

Provenance and caveats, stated plainly:
- Written by Claude (Anthropic) in separate requests from the training data, then
  anonymized (course codes and project names replaced).
- 75 of the 480 have a near-copy (≥80% word overlap) in Tars's training data. Both
  numbers are reported in the main README; the clean subset is the honest one.
- Labels are model-written and not all hand-checked; a few are debatable.

Score any planner end to end (a sentence counts only if the step count, every step's
words, family and skill all match):

    python benchmark/evaluate_benchmark.py --catalog catalogs/example_catalog.json --url http://host/plan
