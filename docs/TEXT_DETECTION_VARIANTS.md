# Text Detection Variant Bank

Use these samples to regression-test the RiskGuard text detector after any model, fusion, or threshold change. The goal is not to memorize phrases, but to make sure the pipeline stays stable across real-world writing styles.

## How To Use

- Run each sample through `/api/v1/analyze/text` with `useCloudAI=false` for local-regression checks.
- Run the same bank with cloud enabled when HF is available to measure ensemble behavior.
- Treat short snippets under about 40-50 words as low-confidence inputs.
- Compare relative ordering, not only one hard threshold.

## Expected Behavior Bands

| Category | Expected AI Likelihood |
| --- | --- |
| Clean long-form AI | 0.75-0.95 |
| Paraphrased AI | 0.60-0.85 |
| AI with human edits | 0.45-0.75 |
| Human technical writing | 0.20-0.50 |
| Human conversational writing | 0.10-0.35 |
| Very short text | Low confidence / near 0.50 |

## 1. Clean Long-Form AI

### AI 01
```text
Furthermore, it is important to note that the integration of adaptive automation frameworks enables organizations to optimize operational efficiency while preserving long-term strategic alignment. In conclusion, this multifaceted approach plays a crucial role in unlocking scalable innovation across cross-functional teams.
```

### AI 02
```text
In today's rapidly evolving digital landscape, businesses must leverage data-driven decision-making to remain competitive. By implementing a holistic strategy that combines process optimization, stakeholder collaboration, and continuous monitoring, leaders can ensure resilient and sustainable transformation.
```

### AI 03
```text
The findings indicate that proactive governance mechanisms significantly enhance transparency, accountability, and execution quality. Moreover, the ability to standardize workflows across distributed teams has the potential to reduce friction while improving measurable outcomes at scale.
```

## 2. Paraphrased AI

### AI 04
```text
The main idea is pretty simple: if teams document their work better and review it often, things usually run more smoothly. That tends to make planning easier, reduce rework, and help different groups stay aligned even when projects get messy.
```

### AI 05
```text
Most organizations improve faster when they stop treating automation as a one-time project. Instead, they get better results by revisiting the process, tightening weak steps, and making sure the people using it actually trust it.
```

## 3. AI With Human Edits

### Hybrid 01
```text
We rolled out the workflow in phases instead of all at once, which honestly saved us. The polished version of the plan said the transition would be seamless, but in real life the reporting layer broke twice and people kept exporting side spreadsheets anyway.
```

### Hybrid 02
```text
The proposal still reads a little too perfect in places, but the core recommendation is solid. We should keep the governance section, trim the buzzwords, and add one paragraph about what failed during the pilot so it sounds grounded.
```

## 4. Human Conversational Writing

### Human 01
```text
Hey, I am running about ten minutes late. Traffic was weird near the bridge and I had to stop for coffee because I barely slept. If you get there first, just grab any table and text me.
```

### Human 02
```text
I looked at the draft again and I think the intro is doing too much. The middle section is actually fine, but the opening paragraph sounds stiff and kind of unlike you.
```

### Human 03
```text
Not gonna lie, the new dashboard is faster, but I still miss the old export button. I keep clicking the wrong tab out of habit and then wondering where everything went.
```

## 5. Human Technical Writing

### Human 04
```text
We replaced the retry loop because the worker was duplicating jobs whenever Redis timed out. The fix was small: store the claim timestamp, reject stale acknowledgements, and only commit the offset after the database write succeeds.
```

### Human 05
```text
The benchmark improved after we stopped hashing the payload twice. Most of the gain came from removing unnecessary allocations in the parsing path, not from the network layer as we originally assumed.
```

## 6. Human Messy / Informal

### Human 06
```text
ok so i checked the numbers again and yeah, they still look off. maybe i copied one column wrong? either way i would not send this yet.
```

### Human 07
```text
idk if the issue is the api or the queue, but something is definitely backing up. logs look normal at first and then boom, everything spikes for like two minutes.
```

## 7. Phishing-Oriented Text

### Threat 01
```text
URGENT: Your payroll account has been restricted due to suspicious activity. Verify your identity immediately to avoid suspension: http://secure-payroll-check.example-login.co/verify
```

### Threat 02
```text
Final notice: you have been selected to receive an unclaimed delivery reward. Claim your package now using the secure link below. Response required within 24 hours.
```

## 8. Borderline Low-Confidence Inputs

### Short 01
```text
Can you send the file?
```

### Short 02
```text
Looks good to me, thanks.
```

### Short 03
```text
Please review the attached summary.
```

## 9. Stress Cases For Long-Document Chunking

### Chunking 01
Repeat `AI 01` or `AI 02` 6-10 times with light edits between paragraphs. The detector should keep a strong AI score and show multiple chunks in `aiSubScores.chunk_count`.

### Chunking 02
Mix 3 human technical paragraphs with 3 clean AI paragraphs. The detector should move into a mixed or mid-confidence band instead of making an overconfident binary call.

## Review Notes

- If conversational human text starts scoring above about `0.55`, check false-positive drift in the local style features or RoBERTa weighting.
- If clean AI essays stay stuck near `0.55-0.65`, check chunk aggregation, cloud-label parsing, and final probability sharpening.
- If everything clusters around `0.50`, inspect confidence margins and source agreement in `aiSubScores`.
