# Case Study Report — Data Analyst 2025
## Talent Match Intelligence System

---

**Candidate:** Ninditya S.N.A.
**Email:** ninditya.sna025@gmail.com
**Repository:** https://github.com/ninditya/talent-match-intelligence
**Live App:** https://ninditya-talent-match-intelligence.streamlit.app/

---

## Executive Summary

Company X faces a critical challenge in succession planning: how to systematically identify which employees most closely match the profile of proven top performers. This project builds a **Talent Match Intelligence** system that answers that question at scale.

**What was built:**

1. **Success Pattern Discovery** — a data-driven analysis of 2,010 employees across 5 years of performance data, identifying what truly differentiates Rating-5 employees across competencies, psychometrics, behavioral assessments, and organizational context.

2. **SQL Matching Algorithm** — a 17-CTE parameterized query that computes how closely any employee matches a manager-defined benchmark profile, producing interpretable TV → TGV → Final Match Rate scores.

3. **AI-Powered Talent App** — a publicly deployed Streamlit dashboard that accepts runtime vacancy inputs, computes match scores dynamically, generates LLM-produced job profiles via OpenRouter, and visualizes insights through interactive charts.

**Key outcome:** Any manager can now define a vacancy, select 1–3 top performers as benchmark, and instantly receive a ranked list of 2,010 employees scored against that profile — with full transparency into which competencies, traits, and work preferences drive the match.

---

## Section 1 — Success Pattern Discovery

### 1.1 Dataset Overview

| Table | Rows | Notes |
|---|---|---|
| employees | 2,010 | Core entity |
| performance_yearly | 10,050 | 5 years (2021–2025) |
| profiles_psych | 2,010 | One row per employee |
| papi_scores | 40,200 | 20 scales × 2,010 employees |
| competencies_yearly | 100,500 | 10 pillars × 5 years × 2,010 |
| strengths | 28,140 | 14 CliftonStrengths themes per employee |

**Data quality issues found:**
- Invalid ratings: 15 records with rating=0, 13 with rating=6, 7 with rating=99 → excluded from all analysis
- Null psychometric data: IQ missing for 456 employees (22.7%), GTQ missing for 332 (16.5%) — these are department-level assessment gaps, not data errors
- Invalid MBTI entries: some contained typos (e.g., "INFTJ") → cleaned to 16 valid types only

**High performers (Rating=5):**
- 187 employees qualify as Rating=5 out of 1,975 valid (9.5%)
- Distributed across all three directorates (Commercial, Technology, HR & Corp Affairs)
- Average tenure: 4.3 years vs 4.2 years for others — tenure alone is not a differentiator

---

### 1.2 Competency Execution — Strongest Signal

All 10 competency pillars show significant positive differences for R5 employees. The top performers score consistently higher across every dimension, not just selectively.

| Pillar | Label | R5 Mean | Others Mean | Δ |
|---|---|---|---|---|
| SEA | Social Empathy & Awareness | 5.03 | 2.92 | **+2.10** |
| VCU | Value Creation for Users | 5.01 | 3.17 | **+1.83** |
| CSI | Commercial Savvy & Impact | 5.04 | 3.22 | **+1.82** |
| STO | Synergy & Team Orientation | 4.96 | 3.15 | **+1.81** |
| CEX | Curiosity & Experimentation | 4.41 | 2.96 | +1.44 |
| QDD | Quality Delivery Discipline | 4.56 | 3.16 | +1.40 |
| LIE | Lead, Inspire & Empower | 4.47 | 3.18 | +1.29 |
| GDR | Growth Drive & Resilience | 4.40 | 3.13 | +1.27 |
| IDS | Insight & Decision Sharpness | 4.40 | 3.14 | +1.26 |
| FTC | Forward Thinking & Clarity | 4.39 | 3.17 | +1.21 |

**Insight:** The top 4 differentiators — Social Empathy, Value Creation, Commercial Savvy, and Synergy — point to a success profile built around **people-orientation and business impact**, not just technical execution. R5 employees are not simply harder workers; they operate at the intersection of human connection and commercial results.

---

### 1.3 Work Preferences (PAPI) — Key Differentiators

PAPI differences are smaller in magnitude than competencies, but reveal a clear behavioral signature.

**Positive for R5 (higher = more like top performers):**

| Scale | Label | R5 | Others | Δ |
|---|---|---|---|---|
| Papi_P | Planning | 5.32 | 4.96 | **+0.35** |
| Papi_W | Need to Belong | 5.10 | 4.98 | +0.12 |
| Papi_E | Empathy | 5.16 | 5.06 | +0.10 |
| Papi_N | Need for Achievement | 5.18 | 5.08 | +0.10 |
| Papi_F | Forward Planning | 5.14 | 5.05 | +0.09 |

**Negative for R5 (lower = more like top performers):**

| Scale | Label | R5 | Others | Δ |
|---|---|---|---|---|
| Papi_G | Leadership | 4.61 | 4.97 | **−0.35** |
| Papi_S | Social Harmony | 4.73 | 5.02 | −0.30 |
| Papi_A | Attention to Detail | 4.77 | 5.06 | −0.29 |
| Papi_T | Tenacity | 4.73 | 4.98 | −0.25 |

**Insight:** The counterintuitive finding — R5 employees score *lower* on the PAPI Leadership (G) scale — reveals that high performers at the current grade level drive results through **collaboration and planning discipline**, not positional authority. They are achievers who belong (Papi_W ↑) and plan (Papi_P ↑), not command-and-control leaders (Papi_G ↓).

---

### 1.4 Psychometric Profile

| Measure | R5 Mean | Others Mean | Δ | Interpretation |
|---|---|---|---|---|
| Pauli | 62.7 | 59.7 | **+3.05** | Mental arithmetic stamina — strongest cognitive differentiator |
| GTQ | 28.6 | 27.4 | **+1.20** | General aptitude — moderate positive signal |
| IQ | 109.0 | 109.6 | −0.59 | No meaningful difference |
| TIKI | 5.5 | 5.5 | +0.02 | No meaningful difference |
| Faxtor | 58.6 | 60.5 | −1.89 | Slightly lower in R5 (internal attention composite) |

**Insight:** Sustained cognitive stamina (Pauli) and aptitude (GTQ) matter, but raw IQ does not differentiate top performers. This aligns with research showing that IQ predicts entry-level performance while sustained effort and structured reasoning (Pauli, GTQ) predict consistent excellence.

---

### 1.5 Behavioral Strengths

**CliftonStrengths — Top themes in R5 (top-5 per employee):**

| Theme | Count | % of R5 |
|---|---|---|
| Futuristic | 37 | 19.8% |
| Restorative | 37 | 19.8% |
| Intellection | 35 | 18.7% |
| Self-Assurance | 33 | 17.6% |
| Activator | 30 | 16.0% |
| Strategic | 30 | 16.0% |
| Learner | 29 | 15.5% |
| Belief | 28 | 15.0% |
| Positivity | 28 | 15.0% |
| Analytical | 27 | 14.4% |

**Pattern:** R5 employees cluster around **future-oriented thinking** (Futuristic, Strategic, Forward Planning) combined with **self-driven problem solving** (Restorative, Activator, Self-Assurance). This maps directly to the competency profile: visionary problem-solvers who take initiative without waiting for permission.

**DISC Type:**
No single DISC type dominates R5. The distribution is spread across CD (9.6%), SI (9.1%), CI (8.6%), DI (8.6%), DC (8.6%). High performance is not style-dependent — it's execution-dependent.

---

### 1.6 Contextual Factors

- **Tenure:** R5 avg 4.3 yrs vs 4.2 yrs — virtually identical. Tenure alone does not predict top performance.
- **Grade:** R5 employees exist at all three grade levels (III, IV, V), confirming the pattern is not grade-specific.
- **Directorate:** R5 representation is proportional across all three directorates.

---

### 1.7 Success Formula

Based on the above analysis, the weighted Success Formula is:

```
Final Match Rate =
    0.30 × Cognitive Ability Score
  + 0.20 × Work Preferences Score
  + 0.25 × Competency Execution Score
  + 0.15 × Behavioral Strengths Score
  + 0.10 × Contextual Fit Score
```

**Weight Rationale:**

| TGV | Weight | Justification |
|---|---|---|
| **Cognitive Ability** | 0.30 | Pauli (+3.05) and GTQ (+1.20) show meaningful gaps; cognitive capacity is the most objectively measurable predictor |
| **Competency Execution** | 0.25 | All 10 pillars differ significantly (+1.2 to +2.1); competencies reflect demonstrated behavior in role, not just potential |
| **Work Preferences** | 0.20 | Planning and achievement orientation create the daily behaviors that translate potential into results |
| **Behavioral Strengths** | 0.15 | CliftonStrengths show a clear future-oriented, self-driven theme cluster; DISC diversity means categorical match is secondary |
| **Contextual Fit** | 0.10 | Tenure and grade show minimal differentiation — included for organizational context, not predictive power |

Within each TGV, all Talent Variables (TVs) carry equal weight unless overridden via `weights_config`.

---

## Section 2 — SQL Logic & Algorithm

### 2.1 Approach

The matching algorithm is implemented as a parameterized SQL query using 17 modular CTEs. It is designed to run entirely on-the-fly given a `job_vacancy_id` — no pre-computation, no hardcoded employee IDs.

**Script:** `sql/matching_algorithm.sql`

### 2.2 CTE Architecture

```
CTE 1:  benchmark_employees      → Unpack selected benchmark IDs from talent_benchmarks
CTE 2:  benchmark_psych          → Psychometric scores for benchmarks
CTE 3:  baseline_psych           → PERCENTILE_CONT(0.5) medians per psych TV
CTE 4:  benchmark_papi           → All 20 PAPI scales pivoted wide for benchmarks
CTE 5:  baseline_papi            → Median per PAPI scale across benchmarks
CTE 6:  baseline_competency      → Median per pillar (latest year) for benchmarks
CTE 7:  benchmark_disc_mode      → MODE() DISC type across benchmarks (categorical baseline)
CTE 8:  benchmark_mbti_mode      → MODE() valid MBTI type across benchmarks
CTE 9:  benchmark_strength_pool  → Pooled unique top-5 CliftonStrengths themes
CTE 10: candidate_info           → All employees + org context (grade, role, directorate)
CTE 11: candidate_psych          → Psychometric scores per candidate
CTE 12: candidate_papi           → All 20 PAPI scales pivoted wide per candidate
CTE 13: candidate_strengths_overlap → Top-5 theme overlap count per candidate
CTE 14: tv_match_rates_long      → Per-employee × per-TV match rate (long format)
CTE 15: tgv_match_rates          → AVG of TV match rates within each TGV
CTE 16: tgv_weights              → Hardcoded TGV weights (overridable)
CTE 17: final_match_rates        → Weighted average of TGV rates = Final Match Rate
```

### 2.3 Scoring Formulas

**Numeric TV (higher is better):**
```sql
LEAST(100, ROUND(user_score / NULLIF(baseline_score, 0) * 100, 2))
```

**Numeric TV (lower is better — inverse scales Papi_Z, Papi_K):**
```sql
LEAST(100, GREATEST(0, ROUND(
    (2 * baseline_score - user_score) / NULLIF(baseline_score, 0) * 100, 2
)))
```

**Categorical TV (DISC, MBTI — exact match):**
```sql
CASE WHEN user_val = baseline_val THEN 100.0 ELSE 0.0 END
```
→ NULL when either value is missing (no penalty for untested data)

**CliftonStrengths overlap:**
```sql
ROUND(overlap_count::NUMERIC / 5 * 100, 2)
-- overlap_count = count of candidate's top-5 themes in benchmark pool
```

**TGV match rate:**
```sql
AVG(tv_match_rate)  -- NULLs excluded (missing data is skipped, not penalized)
```

**Final match rate:**
```sql
SUM(tgv_match_rate * weight) / SUM(weight)
-- weights: Cognitive 0.30 + Competency 0.25 + Work Prefs 0.20 +
--          Behavioral 0.15 + Contextual 0.10 = 1.00
```

### 2.4 Sample Output (vacancy with 3 benchmark employees)

The query returns one row per employee × TV combination. Summary view (per employee):

| employee_id | fullname | final_match_rate | Cognitive | Competency | Work Prefs | Behavioral | Contextual |
|---|---|---|---|---|---|---|---|
| EMP101226 | Yoga Erlangga Mahendra | 92.52% | 92.2% | 98.0% | 86.8% | 86.7% | 100.0% |
| EMP101353 | Prasetyo Halim | 89.85% | 88.1% | 96.5% | 84.2% | 80.0% | 100.0% |
| EMP101428 | Umar Wibowo | 89.05% | 90.3% | 94.2% | 83.1% | 80.0% | 95.0% |

Full output schema:

| Column | Description |
|---|---|
| employee_id | Candidate ID |
| fullname | Full name |
| directorate | Organizational unit |
| role | Position title |
| grade | Grade level |
| tgv_name | Talent Group Variable (e.g., Cognitive Ability) |
| tv_name | Talent Variable (e.g., IQ Score, PAPI Planning) |
| baseline_score | Benchmark median for this TV |
| user_score | Candidate score for this TV |
| tv_match_rate | Match % for this TV (0–100) |
| tgv_match_rate | Avg/weighted match within TGV |
| final_match_rate | Weighted overall match % |

---

## Section 3 — AI App & Dashboard

### 3.1 Live Deployment

**URL:** https://ninditya-talent-match-intelligence.streamlit.app/

**Stack:** Streamlit 1.40 · Python 3.11 · Supabase (Postgres) · OpenRouter (MiniMax M2.5 free) · Plotly 5.24

### 3.2 Runtime Inputs

When a manager submits the form, the app:
1. Writes a new `talent_benchmarks` row with a unique `JV-XXXXXXXX` vacancy ID
2. Recomputes baselines dynamically from the selected benchmark employees
3. Runs the Python matching algorithm against all 2,010 employees
4. Calls OpenRouter LLM to generate a structured job profile
5. Renders all visualizations and ranked results

**Form fields:**
- Role Name (text)
- Job Level (Entry / Junior / Middle / Senior / Manager / Director)
- Role Purpose (1–2 sentences)
- Benchmark Employees (multiselect, max 3, Rating=5 only)

### 3.3 AI-Generated Job Profile

The app calls OpenRouter (MiniMax M2.5 free tier) with a structured prompt that includes:
- Role name, level, and purpose
- TGV benchmark averages (numeric context for the LLM)
- Top CliftonStrengths themes from the benchmark pool

The LLM returns structured JSON:
```json
{
  "job_requirements": ["6+ years experience...", "Strong analytical skills..."],
  "job_description": "2–3 sentence narrative...",
  "key_competencies": ["Strategic Thinking", "Data-Driven Decision Making", ...]
}
```

### 3.4 Dashboard Visualizations

**Tab 1 — Job Profile:** AI-generated requirements, description, key competencies, benchmark employee list.

**Tab 2 — Ranked Talent:** Full 2,010-employee ranked table with search and minimum match % filter. Color-gradient on final_match_rate column.

**Tab 3 — Dashboard:**
- Match rate distribution histogram (all 2,010 candidates)
- Top-15 candidates horizontal bar chart
- TGV heatmap for top-20 candidates (employee × TGV grid)

**Tab 4 — Candidate Detail:**
- TGV radar chart (candidate vs benchmark = 100%)
- TV strengths & gaps horizontal bar (all TVs sorted, 80% threshold line)
- Full TV-level detail table with color gradient

### 3.5 Example Flow

```
Input:  Role = "Head of Digital Marketing"
        Level = Manager
        Purpose = "Drive brand growth and digital acquisition"
        Benchmarks = [EMP100010, EMP100011, EMP100012]

Output: Vacancy ID = JV-D7F4DF9A
        Top match = Yoga Erlangga Mahendra (92.52%)
        AI profile generated in ~8 seconds
        Full ranked table of 2,010 employees
```

---

## Section 4 — Conclusion

### What Worked

- The **competency execution signal** is overwhelmingly the strongest predictor of Rating=5 (all 10 pillars Δ > +1.2). Any company seeking to replicate this approach should prioritize behavioral competency assessments over psychometric scores.
- **Pauli (mental arithmetic stamina)** was the best psychometric differentiator — not IQ — which suggests cognitive endurance matters more than peak intelligence for sustained high performance.
- The **counterintuitive PAPI finding** (R5 scores lower on Leadership/G) adds real analytical value: it warns against promoting people based on leadership style alone rather than execution results.

### Challenges

- **ERD vs. reality mismatch:** The case study brief mentioned GTQ1–GTQ5 and Tiki1–Tiki4 as separate columns, but the actual database stores single composite columns (`gtq`, `tiki`). Discovering and adapting to this required iterating through the live schema rather than relying on documentation.
- **Model availability:** OpenRouter free-tier models deprecated without notice. Required live API querying to identify a working model (`minimax/minimax-m2.5:free`).
- **Pagination:** Supabase PostgREST caps at 1,000 rows per request. A custom paginated `fetch_table()` function was built to handle the full 2,010-employee dataset.

### Ideas for Improvement

1. **Longitudinal weighting:** Use 5-year competency trend (slope) instead of single latest-year score — an employee improving rapidly may be a better bet than one plateauing at a high level.
2. **Role-specific Success Formulas:** Train separate weight sets per job family (e.g., commercial roles weight Papi_P higher; technical roles weight GTQ and Cognitive higher).
3. **Ensemble baseline:** Replace median with a weighted blend of the 3 benchmark employees based on their performance trajectory, not just latest rating.
4. **Interpretable gap analysis:** Auto-generate a personalized development plan for each candidate highlighting their top 3 gaps and suggested interventions.
5. **Real-time retraining:** As new performance ratings arrive annually, automatically re-run the EDA and update the Success Formula weights.

---

*Analysis conducted on Supabase (Postgres) · Python 3.11 · Pandas · Plotly · Streamlit*
*Repository: https://github.com/ninditya/talent-match-intelligence*
*App: https://ninditya-talent-match-intelligence.streamlit.app/*
