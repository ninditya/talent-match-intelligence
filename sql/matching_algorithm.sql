-- ============================================================
-- Talent Match Intelligence — Matching Algorithm
-- Case Study DA 2025
-- ============================================================
-- Usage: replace :job_vacancy_id with the target vacancy ID.
-- All CTEs are modular; each step is documented inline.
-- ============================================================

-- ============================================================
-- STEP 0: Create talent_benchmarks table (run once)
-- ============================================================
CREATE TABLE IF NOT EXISTS talent_benchmarks (
    job_vacancy_id      TEXT PRIMARY KEY,
    role_name           TEXT NOT NULL,
    job_level           TEXT,
    role_purpose        TEXT,
    selected_talent_ids TEXT[],          -- array of employee_ids with rating=5
    weights_config      JSONB            -- optional custom weights per TV/TGV
);

-- ============================================================
-- STEP 1: TV Definitions
-- Maps each Talent Variable (TV) to its source column,
-- TGV group, scoring direction, and default weight.
-- ============================================================
CREATE TABLE IF NOT EXISTS tv_definitions (
    tv_id           SERIAL PRIMARY KEY,
    tgv_name        TEXT    NOT NULL,   -- e.g., 'Cognitive Ability'
    tv_name         TEXT    NOT NULL,   -- e.g., 'IQ Score'
    source_table    TEXT    NOT NULL,   -- e.g., 'profiles_psych'
    source_column   TEXT    NOT NULL,   -- e.g., 'iq'
    data_type       TEXT    NOT NULL,   -- 'numeric' | 'categorical'
    higher_is_better BOOLEAN DEFAULT TRUE,
    tv_weight       NUMERIC DEFAULT 1.0 -- relative weight within TGV
);

-- Seed TV definitions (run once; adjust weights after Step 1 analysis)
-- Aligned to actual ERD: profiles_psych has iq, gtq (int), tiki (int), pauli, faxtor
INSERT INTO tv_definitions (tgv_name, tv_name, source_table, source_column, data_type, higher_is_better, tv_weight)
VALUES
-- Cognitive Ability (TGV weight: 0.30)
('Cognitive Ability', 'IQ Score',     'profiles_psych', 'iq',     'numeric', TRUE, 1.5),
('Cognitive Ability', 'GTQ Score',    'profiles_psych', 'gtq',    'numeric', TRUE, 1.5),
('Cognitive Ability', 'TIKI Score',   'profiles_psych', 'tiki',   'numeric', TRUE, 1.0),
('Cognitive Ability', 'Pauli Score',  'profiles_psych', 'pauli',  'numeric', TRUE, 1.0),
('Cognitive Ability', 'Faxtor Score', 'profiles_psych', 'faxtor', 'numeric', TRUE, 1.0),
-- Work Preferences PAPI (TGV weight: 0.20)
('Work Preferences', 'PAPI Need for Achievement (N)', 'papi_scores', 'Papi_N', 'numeric', TRUE, 1.0),
('Work Preferences', 'PAPI Leadership (G)',           'papi_scores', 'Papi_G', 'numeric', TRUE, 1.0),
('Work Preferences', 'PAPI Attention to Detail (A)',  'papi_scores', 'Papi_A', 'numeric', TRUE, 1.0),
('Work Preferences', 'PAPI Work Pace (L)',            'papi_scores', 'Papi_L', 'numeric', TRUE, 1.0),
('Work Preferences', 'PAPI Planning (P)',             'papi_scores', 'Papi_P', 'numeric', TRUE, 1.0),
-- note: Papi_Z and Papi_K are inverse scales (higher=worse)
('Work Preferences', 'PAPI Avoidance of Change (Z)', 'papi_scores', 'Papi_Z', 'numeric', FALSE, 0.8),
('Work Preferences', 'PAPI Conformity (K)',           'papi_scores', 'Papi_K', 'numeric', FALSE, 0.8),
-- Contextual Fit (TGV weight: 0.10)
('Contextual Fit', 'Years of Service', 'employees', 'years_of_service_months', 'numeric', TRUE, 1.0),
('Contextual Fit', 'Grade Match',      'employees', 'grade_id',                'categorical', TRUE, 1.0)
ON CONFLICT DO NOTHING;

-- ============================================================
-- MAIN MATCHING QUERY
-- Replace :job_vacancy_id with actual vacancy ID at runtime
-- ============================================================

WITH

-- ----------------------------------------------------------------
-- CTE 1: benchmark_employees
-- Pull the selected benchmark employee IDs for the given vacancy.
-- These are the Rating=5 employees chosen by the manager.
-- ----------------------------------------------------------------
benchmark_employees AS (
    SELECT
        tb.job_vacancy_id,
        tb.role_name,
        tb.job_level,
        tb.role_purpose,
        tb.weights_config,
        UNNEST(tb.selected_talent_ids) AS benchmark_employee_id
    FROM talent_benchmarks tb
    WHERE tb.job_vacancy_id = :job_vacancy_id
),

-- ----------------------------------------------------------------
-- CTE 2: benchmark_psych_scores
-- Collect psychometric TV values for benchmarks from profiles_psych.
-- Actual ERD columns: iq, gtq (int), tiki (int), pauli, faxtor
-- ----------------------------------------------------------------
benchmark_psych AS (
    SELECT
        be.job_vacancy_id,
        be.benchmark_employee_id,
        pp.iq,
        pp.gtq,
        pp.tiki,
        pp.pauli,
        pp.faxtor
    FROM benchmark_employees be
    JOIN profiles_psych pp ON pp.employee_id = be.benchmark_employee_id
),

-- ----------------------------------------------------------------
-- CTE 3: baseline_psych
-- Compute MEDIAN of each psychometric TV across all benchmarks.
-- Median is robust to outliers — preferred over mean for small samples.
-- ----------------------------------------------------------------
baseline_psych AS (
    SELECT
        job_vacancy_id,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY iq)    AS baseline_iq,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gtq)   AS baseline_gtq,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tiki)  AS baseline_tiki,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pauli) AS baseline_pauli,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY faxtor)AS baseline_faxtor
    FROM benchmark_psych
    GROUP BY job_vacancy_id
),

-- ----------------------------------------------------------------
-- CTE 4: benchmark_papi
-- Collect PAPI scales for benchmarks, pivoted to wide format.
-- ----------------------------------------------------------------
benchmark_papi AS (
    SELECT
        be.job_vacancy_id,
        be.benchmark_employee_id,
        MAX(CASE WHEN ps.scale_code = 'Papi_N' THEN ps.score END) AS papi_n,
        MAX(CASE WHEN ps.scale_code = 'Papi_G' THEN ps.score END) AS papi_g,
        MAX(CASE WHEN ps.scale_code = 'Papi_A' THEN ps.score END) AS papi_a,
        MAX(CASE WHEN ps.scale_code = 'Papi_L' THEN ps.score END) AS papi_l,
        MAX(CASE WHEN ps.scale_code = 'Papi_P' THEN ps.score END) AS papi_p,
        MAX(CASE WHEN ps.scale_code = 'Papi_Z' THEN ps.score END) AS papi_z,
        MAX(CASE WHEN ps.scale_code = 'Papi_K' THEN ps.score END) AS papi_k,
        MAX(CASE WHEN ps.scale_code = 'Papi_I' THEN ps.score END) AS papi_i,
        MAX(CASE WHEN ps.scale_code = 'Papi_T' THEN ps.score END) AS papi_t,
        MAX(CASE WHEN ps.scale_code = 'Papi_V' THEN ps.score END) AS papi_v,
        MAX(CASE WHEN ps.scale_code = 'Papi_S' THEN ps.score END) AS papi_s,
        MAX(CASE WHEN ps.scale_code = 'Papi_B' THEN ps.score END) AS papi_b,
        MAX(CASE WHEN ps.scale_code = 'Papi_O' THEN ps.score END) AS papi_o,
        MAX(CASE WHEN ps.scale_code = 'Papi_R' THEN ps.score END) AS papi_r,
        MAX(CASE WHEN ps.scale_code = 'Papi_D' THEN ps.score END) AS papi_d,
        MAX(CASE WHEN ps.scale_code = 'Papi_C' THEN ps.score END) AS papi_c,
        MAX(CASE WHEN ps.scale_code = 'Papi_E' THEN ps.score END) AS papi_e,
        MAX(CASE WHEN ps.scale_code = 'Papi_F' THEN ps.score END) AS papi_f,
        MAX(CASE WHEN ps.scale_code = 'Papi_W' THEN ps.score END) AS papi_w,
        MAX(CASE WHEN ps.scale_code = 'Papi_X' THEN ps.score END) AS papi_x
    FROM benchmark_employees be
    JOIN papi_scores ps ON ps.employee_id = be.benchmark_employee_id
    GROUP BY be.job_vacancy_id, be.benchmark_employee_id
),

-- ----------------------------------------------------------------
-- CTE 5: baseline_papi
-- Median PAPI scores across benchmarks.
-- ----------------------------------------------------------------
baseline_papi AS (
    SELECT
        job_vacancy_id,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_n) AS baseline_papi_n,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_g) AS baseline_papi_g,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_a) AS baseline_papi_a,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_l) AS baseline_papi_l,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_p) AS baseline_papi_p,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_z) AS baseline_papi_z,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_k) AS baseline_papi_k,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_i) AS baseline_papi_i,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_t) AS baseline_papi_t,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_v) AS baseline_papi_v
    FROM benchmark_papi
    GROUP BY job_vacancy_id
),

-- ----------------------------------------------------------------
-- CTE 6: baseline_competency
-- Average competency pillar scores for benchmarks (latest year).
-- ----------------------------------------------------------------
baseline_competency AS (
    SELECT
        be.job_vacancy_id,
        cy.pillar_code,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY cy.score) AS baseline_comp_score
    FROM benchmark_employees be
    JOIN competencies_yearly cy ON cy.employee_id = be.benchmark_employee_id
    WHERE cy.year = (SELECT MAX(year) FROM competencies_yearly)
    GROUP BY be.job_vacancy_id, cy.pillar_code
),

-- ----------------------------------------------------------------
-- CTE 7: candidate_info
-- All employees enriched with org context.
-- ----------------------------------------------------------------
candidate_info AS (
    SELECT
        e.employee_id,
        e.fullname,
        e.years_of_service_months,
        e.grade_id,
        dg.name                        AS grade,
        dp.name                        AS role,
        dd.name                        AS directorate,
        ddept.name                     AS department,
        ddiv.name                      AS division
    FROM employees e
    LEFT JOIN dim_grades       dg    ON dg.grade_id         = e.grade_id
    LEFT JOIN dim_positions    dp    ON dp.position_id      = e.position_id
    LEFT JOIN dim_directorates dd    ON dd.directorate_id   = e.directorate_id
    LEFT JOIN dim_departments  ddept ON ddept.department_id = e.department_id
    LEFT JOIN dim_divisions    ddiv  ON ddiv.division_id    = e.division_id
),

-- ----------------------------------------------------------------
-- CTE 8: candidate_psych
-- Candidate psychometric scores joined from profiles_psych.
-- Actual ERD columns: iq, gtq (int), tiki (int), pauli, faxtor
-- ----------------------------------------------------------------
candidate_psych AS (
    SELECT
        ci.employee_id,
        ci.fullname,
        ci.grade,
        ci.role,
        ci.directorate,
        pp.iq,
        pp.gtq,
        pp.tiki,
        pp.pauli,
        pp.faxtor
    FROM candidate_info ci
    LEFT JOIN profiles_psych pp ON pp.employee_id = ci.employee_id
),

-- ----------------------------------------------------------------
-- CTE 9: candidate_papi
-- Candidate PAPI scores pivoted to wide format.
-- ----------------------------------------------------------------
candidate_papi AS (
    SELECT
        employee_id,
        MAX(CASE WHEN scale_code = 'Papi_N' THEN score END) AS papi_n,
        MAX(CASE WHEN scale_code = 'Papi_G' THEN score END) AS papi_g,
        MAX(CASE WHEN scale_code = 'Papi_A' THEN score END) AS papi_a,
        MAX(CASE WHEN scale_code = 'Papi_L' THEN score END) AS papi_l,
        MAX(CASE WHEN scale_code = 'Papi_P' THEN score END) AS papi_p,
        MAX(CASE WHEN scale_code = 'Papi_Z' THEN score END) AS papi_z,
        MAX(CASE WHEN scale_code = 'Papi_K' THEN score END) AS papi_k,
        MAX(CASE WHEN scale_code = 'Papi_I' THEN score END) AS papi_i,
        MAX(CASE WHEN scale_code = 'Papi_T' THEN score END) AS papi_t,
        MAX(CASE WHEN scale_code = 'Papi_V' THEN score END) AS papi_v
    FROM papi_scores
    GROUP BY employee_id
),

-- ----------------------------------------------------------------
-- CTE 10: tv_match_rates_long
-- Compute per-employee, per-TV match rate in long format.
-- Numeric: candidate_score / baseline_score * 100 (capped at 100)
-- Inverse scale: (2*baseline - candidate) / baseline * 100
-- Categorical: 100 if match, 0 if not
-- ----------------------------------------------------------------
tv_match_rates_long AS (

    -- Cognitive Ability — IQ Score
    SELECT
        cp.employee_id,
        bp.job_vacancy_id,
        'Cognitive Ability'  AS tgv_name,
        'IQ Score'           AS tv_name,
        bp.baseline_iq       AS baseline_score,
        cp.iq                AS user_score,
        LEAST(100, ROUND(COALESCE(cp.iq, 0) / NULLIF(bp.baseline_iq, 0) * 100, 2)) AS tv_match_rate
    FROM candidate_psych cp
    CROSS JOIN baseline_psych bp
    WHERE bp.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- Cognitive Ability — GTQ Score (single composite, per actual ERD)
    SELECT
        cp.employee_id, bp.job_vacancy_id,
        'Cognitive Ability', 'GTQ Score',
        bp.baseline_gtq, cp.gtq,
        LEAST(100, ROUND(COALESCE(cp.gtq, 0) / NULLIF(bp.baseline_gtq, 0) * 100, 2))
    FROM candidate_psych cp CROSS JOIN baseline_psych bp
    WHERE bp.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- Cognitive Ability — TIKI Score (single composite, per actual ERD)
    SELECT
        cp.employee_id, bp.job_vacancy_id,
        'Cognitive Ability', 'TIKI Score',
        bp.baseline_tiki, cp.tiki,
        LEAST(100, ROUND(COALESCE(cp.tiki, 0) / NULLIF(bp.baseline_tiki, 0) * 100, 2))
    FROM candidate_psych cp CROSS JOIN baseline_psych bp
    WHERE bp.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- Cognitive Ability — Pauli Score
    SELECT
        cp.employee_id, bp.job_vacancy_id,
        'Cognitive Ability', 'Pauli Score',
        bp.baseline_pauli, cp.pauli,
        LEAST(100, ROUND(COALESCE(cp.pauli, 0) / NULLIF(bp.baseline_pauli, 0) * 100, 2))
    FROM candidate_psych cp CROSS JOIN baseline_psych bp
    WHERE bp.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- Cognitive Ability — Faxtor Score
    SELECT
        cp.employee_id, bp.job_vacancy_id,
        'Cognitive Ability', 'Faxtor Score',
        bp.baseline_faxtor, cp.faxtor,
        LEAST(100, ROUND(COALESCE(cp.faxtor, 0) / NULLIF(bp.baseline_faxtor, 0) * 100, 2))
    FROM candidate_psych cp CROSS JOIN baseline_psych bp
    WHERE bp.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- Work Preferences TVs (higher is better)
    SELECT
        cpa.employee_id, bpa.job_vacancy_id,
        'Work Preferences', 'PAPI Need for Achievement (N)',
        bpa.baseline_papi_n, cpa.papi_n,
        LEAST(100, ROUND(COALESCE(cpa.papi_n, 0) / NULLIF(bpa.baseline_papi_n, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa
    WHERE bpa.job_vacancy_id = :job_vacancy_id

    UNION ALL

    SELECT
        cpa.employee_id, bpa.job_vacancy_id,
        'Work Preferences', 'PAPI Leadership (G)',
        bpa.baseline_papi_g, cpa.papi_g,
        LEAST(100, ROUND(COALESCE(cpa.papi_g, 0) / NULLIF(bpa.baseline_papi_g, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa
    WHERE bpa.job_vacancy_id = :job_vacancy_id

    UNION ALL

    SELECT
        cpa.employee_id, bpa.job_vacancy_id,
        'Work Preferences', 'PAPI Planning (P)',
        bpa.baseline_papi_p, cpa.papi_p,
        LEAST(100, ROUND(COALESCE(cpa.papi_p, 0) / NULLIF(bpa.baseline_papi_p, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa
    WHERE bpa.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- Inverse scale: lower candidate score is better (Avoidance of Change)
    SELECT
        cpa.employee_id, bpa.job_vacancy_id,
        'Work Preferences', 'PAPI Avoidance of Change (Z)',
        bpa.baseline_papi_z, cpa.papi_z,
        LEAST(100, GREATEST(0, ROUND(
            (2 * bpa.baseline_papi_z - COALESCE(cpa.papi_z, bpa.baseline_papi_z))
            / NULLIF(bpa.baseline_papi_z, 0) * 100, 2
        )))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa
    WHERE bpa.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- Inverse scale: Conformity (K)
    SELECT
        cpa.employee_id, bpa.job_vacancy_id,
        'Work Preferences', 'PAPI Conformity (K)',
        bpa.baseline_papi_k, cpa.papi_k,
        LEAST(100, GREATEST(0, ROUND(
            (2 * bpa.baseline_papi_k - COALESCE(cpa.papi_k, bpa.baseline_papi_k))
            / NULLIF(bpa.baseline_papi_k, 0) * 100, 2
        )))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa
    WHERE bpa.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- Contextual Fit: Years of Service (numeric)
    SELECT
        ci.employee_id,
        bp.job_vacancy_id,
        'Contextual Fit', 'Years of Service',
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY be.years_of_service_months)
            OVER () AS baseline_score,
        ci.years_of_service_months::NUMERIC AS user_score,
        LEAST(100, ROUND(
            COALESCE(ci.years_of_service_months, 0)::NUMERIC
            / NULLIF(
                PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY be.years_of_service_months) OVER (),
                0
            ) * 100, 2
        )) AS tv_match_rate
    FROM candidate_info ci
    CROSS JOIN baseline_psych bp
    JOIN benchmark_employees be ON be.job_vacancy_id = bp.job_vacancy_id
    JOIN candidate_info be_info ON be_info.employee_id = be.benchmark_employee_id
    WHERE bp.job_vacancy_id = :job_vacancy_id
),

-- ----------------------------------------------------------------
-- CTE 11: tgv_match_rates
-- Aggregate TV match rates to TGV level (equal weights within TGV).
-- Custom weights from weights_config can be applied here.
-- ----------------------------------------------------------------
tgv_match_rates AS (
    SELECT
        employee_id,
        job_vacancy_id,
        tgv_name,
        ROUND(AVG(tv_match_rate), 2) AS tgv_match_rate
    FROM tv_match_rates_long
    GROUP BY employee_id, job_vacancy_id, tgv_name
),

-- ----------------------------------------------------------------
-- CTE 12: tgv_weights
-- TGV-level weights derived from the Success Formula.
-- Override via weights_config JSON if custom weights provided.
-- ----------------------------------------------------------------
tgv_weights (tgv_name, weight) AS (
    VALUES
        ('Cognitive Ability',  0.30),
        ('Work Preferences',   0.20),
        ('Competency Execution', 0.25),
        ('Behavioral Strengths', 0.15),
        ('Contextual Fit',     0.10)
),

-- ----------------------------------------------------------------
-- CTE 13: final_match_rates
-- Weighted average of TGV match rates = Final Match Rate per employee.
-- ----------------------------------------------------------------
final_match_rates AS (
    SELECT
        tgv.employee_id,
        tgv.job_vacancy_id,
        ROUND(
            SUM(tgv.tgv_match_rate * COALESCE(tw.weight, 0.20))
            / NULLIF(SUM(COALESCE(tw.weight, 0.20)), 0),
        2) AS final_match_rate
    FROM tgv_match_rates tgv
    LEFT JOIN tgv_weights tw ON tw.tgv_name = tgv.tgv_name
    GROUP BY tgv.employee_id, tgv.job_vacancy_id
)

-- ============================================================
-- FINAL OUTPUT
-- One row per employee × TGV × TV combination.
-- Required columns per case study brief.
-- ============================================================
SELECT
    ci.employee_id,
    ci.fullname,
    ci.directorate,
    ci.role,
    ci.grade,
    tvl.tgv_name,
    tvl.tv_name,
    ROUND(tvl.baseline_score::NUMERIC, 2)   AS baseline_score,
    ROUND(tvl.user_score::NUMERIC, 2)       AS user_score,
    tvl.tv_match_rate,
    tgv.tgv_match_rate,
    fmr.final_match_rate
FROM tv_match_rates_long tvl
JOIN candidate_info      ci  ON ci.employee_id  = tvl.employee_id
JOIN tgv_match_rates     tgv ON tgv.employee_id = tvl.employee_id
                             AND tgv.tgv_name   = tvl.tgv_name
                             AND tgv.job_vacancy_id = tvl.job_vacancy_id
JOIN final_match_rates   fmr ON fmr.employee_id = tvl.employee_id
                             AND fmr.job_vacancy_id = tvl.job_vacancy_id
ORDER BY fmr.final_match_rate DESC, ci.employee_id, tvl.tgv_name, tvl.tv_name;
