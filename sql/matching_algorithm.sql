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
    weights_config      JSONB,           -- optional custom weights per TV/TGV
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- STEP 1: TV Definitions
-- Maps each Talent Variable (TV) to its source column,
-- TGV group, scoring direction, and default weight.
-- ============================================================
CREATE TABLE IF NOT EXISTS tv_definitions (
    tv_id            SERIAL PRIMARY KEY,
    tgv_name         TEXT    NOT NULL,   -- e.g., 'Cognitive Ability'
    tv_name          TEXT    NOT NULL,   -- e.g., 'IQ Score'
    source_table     TEXT    NOT NULL,
    source_column    TEXT    NOT NULL,
    data_type        TEXT    NOT NULL,   -- 'numeric' | 'categorical'
    higher_is_better BOOLEAN DEFAULT TRUE,
    tv_weight        NUMERIC DEFAULT 1.0
);

INSERT INTO tv_definitions (tgv_name, tv_name, source_table, source_column, data_type, higher_is_better, tv_weight)
VALUES
-- Cognitive Ability (TGV weight: 0.30) — 5 TVs
('Cognitive Ability', 'IQ Score',     'profiles_psych', 'iq',     'numeric', TRUE, 1.0),
('Cognitive Ability', 'GTQ Score',    'profiles_psych', 'gtq',    'numeric', TRUE, 1.0),
('Cognitive Ability', 'TIKI Score',   'profiles_psych', 'tiki',   'numeric', TRUE, 1.0),
('Cognitive Ability', 'Pauli Score',  'profiles_psych', 'pauli',  'numeric', TRUE, 1.0),
('Cognitive Ability', 'Faxtor Score', 'profiles_psych', 'faxtor', 'numeric', TRUE, 1.0),
-- Work Preferences / PAPI (TGV weight: 0.20) — all 20 scales
('Work Preferences', 'PAPI Need for Achievement (N)', 'papi_scores', 'Papi_N', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Leadership (G)',           'papi_scores', 'Papi_G', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Attention to Detail (A)',  'papi_scores', 'Papi_A', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Work Pace (L)',            'papi_scores', 'Papi_L', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Planning (P)',             'papi_scores', 'Papi_P', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Initiative (I)',           'papi_scores', 'Papi_I', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Tenacity (T)',             'papi_scores', 'Papi_T', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Vigour (V)',               'papi_scores', 'Papi_V', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Social Harmony (S)',       'papi_scores', 'Papi_S', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Need for Rules (B)',       'papi_scores', 'Papi_B', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Need for Status (O)',      'papi_scores', 'Papi_O', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Emotional Restraint (R)',  'papi_scores', 'Papi_R', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Need for Change (D)',      'papi_scores', 'Papi_D', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Conceptual Thinking (C)', 'papi_scores', 'Papi_C', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Empathy (E)',              'papi_scores', 'Papi_E', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Need to Belong (W)',       'papi_scores', 'Papi_W', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Flexibility (X)',          'papi_scores', 'Papi_X', 'numeric', TRUE,  1.0),
('Work Preferences', 'PAPI Forward Planning (F)',     'papi_scores', 'Papi_F', 'numeric', TRUE,  1.0),
-- Inverse scales: lower score = more aligned with high performers
('Work Preferences', 'PAPI Avoidance of Change (Z)', 'papi_scores', 'Papi_Z', 'numeric', FALSE, 1.0),
('Work Preferences', 'PAPI Conformity (K)',           'papi_scores', 'Papi_K', 'numeric', FALSE, 1.0),
-- Behavioral Strengths (TGV weight: 0.15) — 3 TVs
('Behavioral Strengths', 'DISC Type',                'profiles_psych', 'disc',  'categorical', TRUE, 1.0),
('Behavioral Strengths', 'MBTI Type',                'profiles_psych', 'mbti',  'categorical', TRUE, 1.0),
('Behavioral Strengths', 'CliftonStrengths Overlap', 'strengths',      'theme', 'numeric',     TRUE, 1.0),
-- Contextual Fit (TGV weight: 0.10) — 1 TV
('Contextual Fit', 'Years of Service', 'employees', 'years_of_service_months', 'numeric', TRUE, 1.0)
-- Note: Competency Execution (TGV weight: 0.25) is handled from competencies_yearly
-- and generated dynamically per pillar_code (10 pillars × 1 TV each)
ON CONFLICT DO NOTHING;


-- ============================================================
-- MAIN MATCHING QUERY
-- Replace :job_vacancy_id with actual vacancy ID at runtime.
-- Produces one row per employee × TV combination.
-- ============================================================

WITH

-- ----------------------------------------------------------------
-- CTE 1: benchmark_employees
-- Unpack the selected benchmark employee IDs for the given vacancy.
-- ----------------------------------------------------------------
benchmark_employees AS (
    SELECT
        tb.job_vacancy_id,
        tb.role_name,
        tb.job_level,
        UNNEST(tb.selected_talent_ids) AS benchmark_employee_id
    FROM talent_benchmarks tb
    WHERE tb.job_vacancy_id = :job_vacancy_id
),

-- ----------------------------------------------------------------
-- CTE 2: benchmark_psych
-- Psychometric scores for benchmark employees.
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
-- Median of each psychometric TV across all benchmark employees.
-- PERCENTILE_CONT(0.5) = true median, robust to outliers.
-- ----------------------------------------------------------------
baseline_psych AS (
    SELECT
        job_vacancy_id,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY iq)     AS baseline_iq,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gtq)    AS baseline_gtq,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tiki)   AS baseline_tiki,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pauli)  AS baseline_pauli,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY faxtor) AS baseline_faxtor
    FROM benchmark_psych
    GROUP BY job_vacancy_id
),

-- ----------------------------------------------------------------
-- CTE 4: benchmark_papi
-- All 20 PAPI scales for benchmark employees, pivoted to wide format.
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
        MAX(CASE WHEN ps.scale_code = 'Papi_W' THEN ps.score END) AS papi_w,
        MAX(CASE WHEN ps.scale_code = 'Papi_X' THEN ps.score END) AS papi_x,
        MAX(CASE WHEN ps.scale_code = 'Papi_F' THEN ps.score END) AS papi_f,
        MAX(CASE WHEN ps.scale_code = 'Papi_Z' THEN ps.score END) AS papi_z,  -- inverse
        MAX(CASE WHEN ps.scale_code = 'Papi_K' THEN ps.score END) AS papi_k   -- inverse
    FROM benchmark_employees be
    JOIN papi_scores ps ON ps.employee_id = be.benchmark_employee_id
    GROUP BY be.job_vacancy_id, be.benchmark_employee_id
),

-- ----------------------------------------------------------------
-- CTE 5: baseline_papi
-- Median PAPI scores across benchmarks for all 20 scales.
-- ----------------------------------------------------------------
baseline_papi AS (
    SELECT
        job_vacancy_id,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_n) AS baseline_papi_n,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_g) AS baseline_papi_g,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_a) AS baseline_papi_a,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_l) AS baseline_papi_l,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_p) AS baseline_papi_p,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_i) AS baseline_papi_i,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_t) AS baseline_papi_t,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_v) AS baseline_papi_v,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_s) AS baseline_papi_s,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_b) AS baseline_papi_b,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_o) AS baseline_papi_o,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_r) AS baseline_papi_r,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_d) AS baseline_papi_d,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_c) AS baseline_papi_c,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_e) AS baseline_papi_e,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_w) AS baseline_papi_w,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_x) AS baseline_papi_x,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_f) AS baseline_papi_f,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_z) AS baseline_papi_z,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY papi_k) AS baseline_papi_k
    FROM benchmark_papi
    GROUP BY job_vacancy_id
),

-- ----------------------------------------------------------------
-- CTE 6: baseline_competency
-- Median competency pillar scores for benchmarks (latest year only).
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
-- CTE 7: benchmark_disc_mode
-- Most common DISC type among benchmark employees (categorical baseline).
-- ----------------------------------------------------------------
benchmark_disc_mode AS (
    SELECT
        be.job_vacancy_id,
        MODE() WITHIN GROUP (ORDER BY pp.disc) AS baseline_disc
    FROM benchmark_employees be
    JOIN profiles_psych pp ON pp.employee_id = be.benchmark_employee_id
    WHERE pp.disc IS NOT NULL
    GROUP BY be.job_vacancy_id
),

-- ----------------------------------------------------------------
-- CTE 8: benchmark_mbti_mode
-- Most common valid MBTI type among benchmark employees.
-- ----------------------------------------------------------------
benchmark_mbti_mode AS (
    SELECT
        be.job_vacancy_id,
        MODE() WITHIN GROUP (ORDER BY UPPER(TRIM(pp.mbti))) AS baseline_mbti
    FROM benchmark_employees be
    JOIN profiles_psych pp ON pp.employee_id = be.benchmark_employee_id
    WHERE UPPER(TRIM(pp.mbti)) IN (
        'INTJ','INTP','ENTJ','ENTP','INFJ','INFP','ENFJ','ENFP',
        'ISTJ','ISFJ','ESTJ','ESFJ','ISTP','ISFP','ESTP','ESFP'
    )
    GROUP BY be.job_vacancy_id
),

-- ----------------------------------------------------------------
-- CTE 9: benchmark_strength_pool
-- Distinct top-5 CliftonStrengths themes pooled from all benchmarks.
-- pool_size = number of unique themes in the pool (used as baseline).
-- ----------------------------------------------------------------
benchmark_strength_pool AS (
    SELECT
        be.job_vacancy_id,
        COUNT(DISTINCT s.theme) AS pool_size
    FROM benchmark_employees be
    JOIN strengths s ON s.employee_id = be.benchmark_employee_id AND s.rank <= 5
    WHERE s.theme IS NOT NULL
    GROUP BY be.job_vacancy_id
),

-- ----------------------------------------------------------------
-- CTE 10: candidate_info
-- All employees enriched with org-context dimension lookups.
-- ----------------------------------------------------------------
candidate_info AS (
    SELECT
        e.employee_id,
        e.fullname,
        e.years_of_service_months,
        e.grade_id,
        dg.name  AS grade,
        dp.name  AS role,
        dd.name  AS directorate
    FROM employees e
    LEFT JOIN dim_grades       dg ON dg.grade_id       = e.grade_id
    LEFT JOIN dim_positions    dp ON dp.position_id    = e.position_id
    LEFT JOIN dim_directorates dd ON dd.directorate_id = e.directorate_id
),

-- ----------------------------------------------------------------
-- CTE 11: candidate_psych
-- Candidate psychometric scores from profiles_psych.
-- ----------------------------------------------------------------
candidate_psych AS (
    SELECT
        ci.employee_id,
        pp.iq,
        pp.gtq,
        pp.tiki,
        pp.pauli,
        pp.faxtor,
        pp.disc,
        pp.mbti
    FROM candidate_info ci
    LEFT JOIN profiles_psych pp ON pp.employee_id = ci.employee_id
),

-- ----------------------------------------------------------------
-- CTE 12: candidate_papi
-- All 20 PAPI scales for each candidate, pivoted to wide format.
-- ----------------------------------------------------------------
candidate_papi AS (
    SELECT
        employee_id,
        MAX(CASE WHEN scale_code = 'Papi_N' THEN score END) AS papi_n,
        MAX(CASE WHEN scale_code = 'Papi_G' THEN score END) AS papi_g,
        MAX(CASE WHEN scale_code = 'Papi_A' THEN score END) AS papi_a,
        MAX(CASE WHEN scale_code = 'Papi_L' THEN score END) AS papi_l,
        MAX(CASE WHEN scale_code = 'Papi_P' THEN score END) AS papi_p,
        MAX(CASE WHEN scale_code = 'Papi_I' THEN score END) AS papi_i,
        MAX(CASE WHEN scale_code = 'Papi_T' THEN score END) AS papi_t,
        MAX(CASE WHEN scale_code = 'Papi_V' THEN score END) AS papi_v,
        MAX(CASE WHEN scale_code = 'Papi_S' THEN score END) AS papi_s,
        MAX(CASE WHEN scale_code = 'Papi_B' THEN score END) AS papi_b,
        MAX(CASE WHEN scale_code = 'Papi_O' THEN score END) AS papi_o,
        MAX(CASE WHEN scale_code = 'Papi_R' THEN score END) AS papi_r,
        MAX(CASE WHEN scale_code = 'Papi_D' THEN score END) AS papi_d,
        MAX(CASE WHEN scale_code = 'Papi_C' THEN score END) AS papi_c,
        MAX(CASE WHEN scale_code = 'Papi_E' THEN score END) AS papi_e,
        MAX(CASE WHEN scale_code = 'Papi_W' THEN score END) AS papi_w,
        MAX(CASE WHEN scale_code = 'Papi_X' THEN score END) AS papi_x,
        MAX(CASE WHEN scale_code = 'Papi_F' THEN score END) AS papi_f,
        MAX(CASE WHEN scale_code = 'Papi_Z' THEN score END) AS papi_z,  -- inverse
        MAX(CASE WHEN scale_code = 'Papi_K' THEN score END) AS papi_k   -- inverse
    FROM papi_scores
    GROUP BY employee_id
),

-- ----------------------------------------------------------------
-- CTE 13: candidate_strengths_overlap
-- For each candidate: count of top-5 themes that appear in the
-- benchmark pool. Overlap / 5 * 100 = match %.
-- ----------------------------------------------------------------
candidate_strengths_overlap AS (
    SELECT
        ci.employee_id,
        bdm.job_vacancy_id,
        bsp.pool_size                                                    AS baseline_score,
        COUNT(CASE WHEN s.theme IN (
            SELECT DISTINCT s2.theme
            FROM benchmark_employees be2
            JOIN strengths s2
              ON s2.employee_id = be2.benchmark_employee_id AND s2.rank <= 5
            WHERE be2.job_vacancy_id = bdm.job_vacancy_id
              AND s2.theme IS NOT NULL
        ) THEN 1 END)                                                    AS overlap_count,
        ROUND(
            COUNT(CASE WHEN s.theme IN (
                SELECT DISTINCT s2.theme
                FROM benchmark_employees be2
                JOIN strengths s2
                  ON s2.employee_id = be2.benchmark_employee_id AND s2.rank <= 5
                WHERE be2.job_vacancy_id = bdm.job_vacancy_id
                  AND s2.theme IS NOT NULL
            ) THEN 1 END)::NUMERIC / NULLIF(5, 0) * 100
        , 2)                                                             AS tv_match_rate
    FROM candidate_info ci
    LEFT JOIN strengths s
           ON s.employee_id = ci.employee_id AND s.rank <= 5
    CROSS JOIN benchmark_disc_mode bdm
    JOIN benchmark_strength_pool bsp ON bsp.job_vacancy_id = bdm.job_vacancy_id
    WHERE bdm.job_vacancy_id = :job_vacancy_id
      AND s.theme IS NOT NULL
    GROUP BY ci.employee_id, bdm.job_vacancy_id, bsp.pool_size
),

-- ----------------------------------------------------------------
-- CTE 14: tv_match_rates_long
-- Core logic: compute per-employee, per-TV match rate in long format.
--
-- Formula:
--   Numeric (higher-is-better): candidate / baseline * 100, capped 0–100
--   Numeric (lower-is-better):  (2*baseline - candidate) / baseline * 100
--   Categorical:                exact match = 100, mismatch = 0, NULL = NULL
--
-- NULL user_score → NULL tv_match_rate (not penalized as 0).
-- ----------------------------------------------------------------
tv_match_rates_long AS (

    -- ── Cognitive Ability: IQ Score ──
    SELECT cp.employee_id, bp.job_vacancy_id,
           'Cognitive Ability' AS tgv_name, 'IQ Score' AS tv_name,
           bp.baseline_iq::NUMERIC AS baseline_score, cp.iq::NUMERIC AS user_score,
           LEAST(100, ROUND(cp.iq::NUMERIC / NULLIF(bp.baseline_iq, 0) * 100, 2)) AS tv_match_rate
    FROM candidate_psych cp CROSS JOIN baseline_psych bp
    WHERE bp.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- ── Cognitive Ability: GTQ Score ──
    SELECT cp.employee_id, bp.job_vacancy_id,
           'Cognitive Ability', 'GTQ Score',
           bp.baseline_gtq, cp.gtq::NUMERIC,
           LEAST(100, ROUND(cp.gtq::NUMERIC / NULLIF(bp.baseline_gtq, 0) * 100, 2))
    FROM candidate_psych cp CROSS JOIN baseline_psych bp
    WHERE bp.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- ── Cognitive Ability: TIKI Score ──
    SELECT cp.employee_id, bp.job_vacancy_id,
           'Cognitive Ability', 'TIKI Score',
           bp.baseline_tiki, cp.tiki::NUMERIC,
           LEAST(100, ROUND(cp.tiki::NUMERIC / NULLIF(bp.baseline_tiki, 0) * 100, 2))
    FROM candidate_psych cp CROSS JOIN baseline_psych bp
    WHERE bp.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- ── Cognitive Ability: Pauli Score ──
    SELECT cp.employee_id, bp.job_vacancy_id,
           'Cognitive Ability', 'Pauli Score',
           bp.baseline_pauli, cp.pauli,
           LEAST(100, ROUND(cp.pauli / NULLIF(bp.baseline_pauli, 0) * 100, 2))
    FROM candidate_psych cp CROSS JOIN baseline_psych bp
    WHERE bp.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- ── Cognitive Ability: Faxtor Score ──
    SELECT cp.employee_id, bp.job_vacancy_id,
           'Cognitive Ability', 'Faxtor Score',
           bp.baseline_faxtor, cp.faxtor,
           LEAST(100, ROUND(cp.faxtor / NULLIF(bp.baseline_faxtor, 0) * 100, 2))
    FROM candidate_psych cp CROSS JOIN baseline_psych bp
    WHERE bp.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- ── Work Preferences: all 18 standard PAPI scales (higher = better) ──
    SELECT cpa.employee_id, bpa.job_vacancy_id,
           'Work Preferences', 'PAPI Need for Achievement (N)',
           bpa.baseline_papi_n, cpa.papi_n::NUMERIC,
           LEAST(100, ROUND(cpa.papi_n::NUMERIC / NULLIF(bpa.baseline_papi_n, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Leadership (G)',
           bpa.baseline_papi_g, cpa.papi_g::NUMERIC,
           LEAST(100, ROUND(cpa.papi_g::NUMERIC / NULLIF(bpa.baseline_papi_g, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Attention to Detail (A)',
           bpa.baseline_papi_a, cpa.papi_a::NUMERIC,
           LEAST(100, ROUND(cpa.papi_a::NUMERIC / NULLIF(bpa.baseline_papi_a, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Work Pace (L)',
           bpa.baseline_papi_l, cpa.papi_l::NUMERIC,
           LEAST(100, ROUND(cpa.papi_l::NUMERIC / NULLIF(bpa.baseline_papi_l, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Planning (P)',
           bpa.baseline_papi_p, cpa.papi_p::NUMERIC,
           LEAST(100, ROUND(cpa.papi_p::NUMERIC / NULLIF(bpa.baseline_papi_p, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Initiative (I)',
           bpa.baseline_papi_i, cpa.papi_i::NUMERIC,
           LEAST(100, ROUND(cpa.papi_i::NUMERIC / NULLIF(bpa.baseline_papi_i, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Tenacity (T)',
           bpa.baseline_papi_t, cpa.papi_t::NUMERIC,
           LEAST(100, ROUND(cpa.papi_t::NUMERIC / NULLIF(bpa.baseline_papi_t, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Vigour (V)',
           bpa.baseline_papi_v, cpa.papi_v::NUMERIC,
           LEAST(100, ROUND(cpa.papi_v::NUMERIC / NULLIF(bpa.baseline_papi_v, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Social Harmony (S)',
           bpa.baseline_papi_s, cpa.papi_s::NUMERIC,
           LEAST(100, ROUND(cpa.papi_s::NUMERIC / NULLIF(bpa.baseline_papi_s, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Need for Rules (B)',
           bpa.baseline_papi_b, cpa.papi_b::NUMERIC,
           LEAST(100, ROUND(cpa.papi_b::NUMERIC / NULLIF(bpa.baseline_papi_b, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Need for Status (O)',
           bpa.baseline_papi_o, cpa.papi_o::NUMERIC,
           LEAST(100, ROUND(cpa.papi_o::NUMERIC / NULLIF(bpa.baseline_papi_o, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Emotional Restraint (R)',
           bpa.baseline_papi_r, cpa.papi_r::NUMERIC,
           LEAST(100, ROUND(cpa.papi_r::NUMERIC / NULLIF(bpa.baseline_papi_r, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Need for Change (D)',
           bpa.baseline_papi_d, cpa.papi_d::NUMERIC,
           LEAST(100, ROUND(cpa.papi_d::NUMERIC / NULLIF(bpa.baseline_papi_d, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Conceptual Thinking (C)',
           bpa.baseline_papi_c, cpa.papi_c::NUMERIC,
           LEAST(100, ROUND(cpa.papi_c::NUMERIC / NULLIF(bpa.baseline_papi_c, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Empathy (E)',
           bpa.baseline_papi_e, cpa.papi_e::NUMERIC,
           LEAST(100, ROUND(cpa.papi_e::NUMERIC / NULLIF(bpa.baseline_papi_e, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Need to Belong (W)',
           bpa.baseline_papi_w, cpa.papi_w::NUMERIC,
           LEAST(100, ROUND(cpa.papi_w::NUMERIC / NULLIF(bpa.baseline_papi_w, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Flexibility (X)',
           bpa.baseline_papi_x, cpa.papi_x::NUMERIC,
           LEAST(100, ROUND(cpa.papi_x::NUMERIC / NULLIF(bpa.baseline_papi_x, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id UNION ALL
    SELECT cpa.employee_id, bpa.job_vacancy_id, 'Work Preferences', 'PAPI Forward Planning (F)',
           bpa.baseline_papi_f, cpa.papi_f::NUMERIC,
           LEAST(100, ROUND(cpa.papi_f::NUMERIC / NULLIF(bpa.baseline_papi_f, 0) * 100, 2))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- ── Work Preferences: inverse scales (lower candidate score = better) ──
    SELECT cpa.employee_id, bpa.job_vacancy_id,
           'Work Preferences', 'PAPI Avoidance of Change (Z)',
           bpa.baseline_papi_z, cpa.papi_z::NUMERIC,
           LEAST(100, GREATEST(0, ROUND(
               (2 * bpa.baseline_papi_z - cpa.papi_z::NUMERIC)
               / NULLIF(bpa.baseline_papi_z, 0) * 100, 2
           )))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id

    UNION ALL

    SELECT cpa.employee_id, bpa.job_vacancy_id,
           'Work Preferences', 'PAPI Conformity (K)',
           bpa.baseline_papi_k, cpa.papi_k::NUMERIC,
           LEAST(100, GREATEST(0, ROUND(
               (2 * bpa.baseline_papi_k - cpa.papi_k::NUMERIC)
               / NULLIF(bpa.baseline_papi_k, 0) * 100, 2
           )))
    FROM candidate_papi cpa CROSS JOIN baseline_papi bpa WHERE bpa.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- ── Behavioral Strengths: DISC Type (categorical — exact match) ──
    SELECT cp.employee_id, bdm.job_vacancy_id,
           'Behavioral Strengths', 'DISC Type',
           bdm.baseline_disc::TEXT AS baseline_score,
           cp.disc                 AS user_score,
           CASE
               WHEN cp.disc IS NULL OR bdm.baseline_disc IS NULL THEN NULL
               WHEN cp.disc = bdm.baseline_disc                  THEN 100.0
               ELSE 0.0
           END AS tv_match_rate
    FROM candidate_psych cp
    CROSS JOIN benchmark_disc_mode bdm
    WHERE bdm.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- ── Behavioral Strengths: MBTI Type (categorical — exact valid-type match) ──
    SELECT cp.employee_id, bmm.job_vacancy_id,
           'Behavioral Strengths', 'MBTI Type',
           bmm.baseline_mbti AS baseline_score,
           cp.mbti           AS user_score,
           CASE
               WHEN cp.mbti IS NULL OR bmm.baseline_mbti IS NULL THEN NULL
               WHEN UPPER(TRIM(cp.mbti)) NOT IN (
                   'INTJ','INTP','ENTJ','ENTP','INFJ','INFP','ENFJ','ENFP',
                   'ISTJ','ISFJ','ESTJ','ESFJ','ISTP','ISFP','ESTP','ESFP'
               ) THEN NULL
               WHEN UPPER(TRIM(cp.mbti)) = bmm.baseline_mbti THEN 100.0
               ELSE 0.0
           END AS tv_match_rate
    FROM candidate_psych cp
    CROSS JOIN benchmark_mbti_mode bmm
    WHERE bmm.job_vacancy_id = :job_vacancy_id

    UNION ALL

    -- ── Behavioral Strengths: CliftonStrengths Overlap ──
    -- % of candidate's top-5 themes found in benchmark theme pool
    SELECT cso.employee_id, cso.job_vacancy_id,
           'Behavioral Strengths', 'CliftonStrengths Overlap',
           cso.baseline_score, cso.overlap_count::NUMERIC AS user_score,
           cso.tv_match_rate
    FROM candidate_strengths_overlap cso

    UNION ALL

    -- ── Competency Execution: one TV per pillar, latest year ──
    SELECT
        cy.employee_id,
        bc.job_vacancy_id,
        'Competency Execution'                      AS tgv_name,
        CONCAT('Pillar ', cy.pillar_code)           AS tv_name,
        bc.baseline_comp_score                      AS baseline_score,
        cy.score::NUMERIC                           AS user_score,
        LEAST(100, ROUND(
            cy.score::NUMERIC / NULLIF(bc.baseline_comp_score, 0) * 100, 2
        ))                                          AS tv_match_rate
    FROM competencies_yearly cy
    JOIN baseline_competency bc
      ON bc.pillar_code   = cy.pillar_code
     AND bc.job_vacancy_id = :job_vacancy_id
    WHERE cy.year = (SELECT MAX(year) FROM competencies_yearly)

    UNION ALL

    -- ── Contextual Fit: Years of Service ──
    SELECT
        ci.employee_id,
        bp.job_vacancy_id,
        'Contextual Fit', 'Years of Service',
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY be.years_of_service_months)
            OVER ()                                             AS baseline_score,
        ci.years_of_service_months::NUMERIC                    AS user_score,
        LEAST(100, ROUND(
            ci.years_of_service_months::NUMERIC
            / NULLIF(
                PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY be.years_of_service_months) OVER ()
            , 0) * 100, 2
        ))                                                      AS tv_match_rate
    FROM candidate_info ci
    CROSS JOIN baseline_psych bp
    JOIN benchmark_employees be ON be.job_vacancy_id = bp.job_vacancy_id
    JOIN employees be_emp       ON be_emp.employee_id = be.benchmark_employee_id
    WHERE bp.job_vacancy_id = :job_vacancy_id
),

-- ----------------------------------------------------------------
-- CTE 15: tgv_match_rates
-- Aggregate TV match rates to TGV level (equal weights within TGV).
-- NULLs are excluded from the average — missing data is not penalized.
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
-- CTE 16: tgv_weights
-- TGV-level weights derived from the Success Formula (sums to 1.0).
-- Override via weights_config JSON if custom weights provided.
-- ----------------------------------------------------------------
tgv_weights (tgv_name, weight) AS (
    VALUES
        ('Cognitive Ability',    0.30),
        ('Work Preferences',     0.20),
        ('Competency Execution', 0.25),
        ('Behavioral Strengths', 0.15),
        ('Contextual Fit',       0.10)
),

-- ----------------------------------------------------------------
-- CTE 17: final_match_rates
-- Weighted average of TGV match rates = Final Match Rate per employee.
-- Weight denominator = sum of weights for TGVs that have data.
-- ----------------------------------------------------------------
final_match_rates AS (
    SELECT
        tgv.employee_id,
        tgv.job_vacancy_id,
        ROUND(
            SUM(tgv.tgv_match_rate * COALESCE(tw.weight, 0.20))
            / NULLIF(SUM(COALESCE(tw.weight, 0.20)), 0)
        , 2) AS final_match_rate
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
    tvl.job_vacancy_id,
    tvl.tgv_name,
    tvl.tv_name,
    ROUND(tvl.baseline_score::NUMERIC, 2) AS baseline_score,
    ROUND(tvl.user_score::NUMERIC, 2)     AS user_score,
    tvl.tv_match_rate,
    tgv.tgv_match_rate,
    fmr.final_match_rate
FROM tv_match_rates_long tvl
JOIN candidate_info   ci  ON ci.employee_id   = tvl.employee_id
JOIN tgv_match_rates  tgv ON tgv.employee_id  = tvl.employee_id
                          AND tgv.tgv_name    = tvl.tgv_name
                          AND tgv.job_vacancy_id = tvl.job_vacancy_id
JOIN final_match_rates fmr ON fmr.employee_id = tvl.employee_id
                           AND fmr.job_vacancy_id = tvl.job_vacancy_id
ORDER BY fmr.final_match_rate DESC, ci.employee_id, tvl.tgv_name, tvl.tv_name;
