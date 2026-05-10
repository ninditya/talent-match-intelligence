import os
import uuid
import pandas as pd
from supabase import create_client
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

_sb = None

def _get_secret(key: str) -> str:
    """Read from st.secrets (Streamlit Cloud) or os.environ (local)."""
    try:
        import streamlit as st
        return st.secrets[key]
    except Exception:
        return os.environ[key]

def _client():
    global _sb
    if _sb is None:
        _sb = create_client(_get_secret("SUPABASE_URL"), _get_secret("SUPABASE_KEY"))
    return _sb


def fetch_table(table: str, cols: str = "*", page_size: int = 1000) -> pd.DataFrame:
    """Paginate through all rows — Supabase PostgREST caps at 1,000/request."""
    all_rows, offset = [], 0
    while True:
        r = _client().table(table).select(cols).range(offset, offset + page_size - 1).execute()
        batch = r.data
        all_rows.extend(batch)
        if len(batch) < page_size:
            break
        offset += page_size
    return pd.DataFrame(all_rows)


def get_all_employees() -> pd.DataFrame:
    """Return employee list with latest valid rating (excludes outliers 0, 6, 99)."""
    emps = fetch_table("employees", "employee_id,fullname")
    perf = fetch_table("performance_yearly")
    valid = perf[perf["rating"].isin([1, 2, 3, 4, 5])]
    latest = (
        valid.sort_values("year", ascending=False)
             .drop_duplicates("employee_id")[["employee_id", "rating"]]
    )
    return emps.merge(latest, on="employee_id", how="left")


def get_rating5_employees() -> pd.DataFrame:
    """Return only Rating=5 employees for benchmark selection."""
    all_emps = get_all_employees()
    return all_emps[all_emps["rating"] == 5].reset_index(drop=True)


def upsert_vacancy(role_name: str, job_level: str, role_purpose: str,
                   selected_ids: list, weights_config: dict = None) -> str:
    """Insert a new talent_benchmarks row and return the generated job_vacancy_id."""
    vacancy_id = f"JV-{uuid.uuid4().hex[:8].upper()}"
    row = {
        "job_vacancy_id":      vacancy_id,
        "role_name":           role_name,
        "job_level":           job_level,
        "role_purpose":        role_purpose,
        "selected_talent_ids": selected_ids,
        "weights_config":      weights_config or {},
    }
    _client().table("talent_benchmarks").upsert(row).execute()
    return vacancy_id


# All 20 PAPI scales: (scale_code, label, is_inverse)
# Inverse = lower score is better (Z = Avoidance of Change, K = Conformity)
_PAPI_SCALES = [
    ("Papi_N", "Need for Achievement",  False),
    ("Papi_G", "Leadership",            False),
    ("Papi_A", "Attention to Detail",   False),
    ("Papi_L", "Work Pace",             False),
    ("Papi_P", "Planning",              False),
    ("Papi_I", "Initiative",            False),
    ("Papi_T", "Tenacity",              False),
    ("Papi_V", "Vigour",                False),
    ("Papi_S", "Social Harmony",        False),
    ("Papi_B", "Need for Rules",        False),
    ("Papi_O", "Need for Status",       False),
    ("Papi_R", "Emotional Restraint",   False),
    ("Papi_D", "Need for Change",       False),
    ("Papi_C", "Conceptual Thinking",   False),
    ("Papi_E", "Empathy",               False),
    ("Papi_W", "Need to Belong",        False),
    ("Papi_X", "Flexibility",           False),
    ("Papi_F", "Forward Planning",      False),
    ("Papi_Z", "Avoidance of Change",   True),
    ("Papi_K", "Conformity",            True),
]

_VALID_MBTI = {
    'INTJ', 'INTP', 'ENTJ', 'ENTP', 'INFJ', 'INFP', 'ENFJ', 'ENFP',
    'ISTJ', 'ISFJ', 'ESTJ', 'ESFJ', 'ISTP', 'ISFP', 'ESTP', 'ESFP',
}

_UNSET = object()


def compute_match(vacancy_id: str) -> pd.DataFrame:
    """
    Run the matching algorithm aligned with the 5-TGV Success Formula:
      Cognitive Ability (0.30) | Work Preferences (0.20) | Competency Execution (0.25)
      Behavioral Strengths (0.15) | Contextual Fit (0.10)

    Returns: long-format DataFrame with one row per employee × TV.
    """
    # --- load tables ---
    employees   = fetch_table("employees")
    psych       = fetch_table("profiles_psych")
    papi_raw    = fetch_table("papi_scores")
    comp_yearly = fetch_table("competencies_yearly")
    strengths   = fetch_table("strengths")
    dim_grades  = fetch_table("dim_grades")
    dim_pos     = fetch_table("dim_positions")
    dim_dirs    = fetch_table("dim_directorates")

    vacancy_row = (
        _client().table("talent_benchmarks")
                 .select("*")
                 .eq("job_vacancy_id", vacancy_id)
                 .execute()
    )
    if not vacancy_row.data:
        raise ValueError(f"Vacancy {vacancy_id} not found.")

    vac         = vacancy_row.data[0]
    bench_ids   = vac["selected_talent_ids"]
    weights_cfg = vac.get("weights_config") or {}

    tgv_weights = {
        "Cognitive Ability":    weights_cfg.get("Cognitive Ability",    0.30),
        "Work Preferences":     weights_cfg.get("Work Preferences",     0.20),
        "Competency Execution": weights_cfg.get("Competency Execution", 0.25),
        "Behavioral Strengths": weights_cfg.get("Behavioral Strengths", 0.15),
        "Contextual Fit":       weights_cfg.get("Contextual Fit",       0.10),
    }

    # --- pivot PAPI to wide format (all 20 scales) ---
    papi_wide = (
        papi_raw.pivot(index="employee_id", columns="scale_code", values="score")
                .reset_index()
    )

    # --- enrich employees ---
    emp = (
        employees
        .merge(dim_grades.rename(columns={"name": "grade"})[["grade_id", "grade"]],
               on="grade_id", how="left")
        .merge(dim_pos.rename(columns={"name": "role"})[["position_id", "role"]],
               on="position_id", how="left")
        .merge(dim_dirs.rename(columns={"name": "directorate"})[["directorate_id", "directorate"]],
               on="directorate_id", how="left")
        .merge(psych, on="employee_id", how="left")
        .merge(papi_wide, on="employee_id", how="left")
    )

    # --- benchmark subset ---
    bench_df = emp[emp["employee_id"].isin(bench_ids)]

    def median(col):
        if col not in bench_df.columns:
            return None
        s = bench_df[col].dropna()
        return float(s.median()) if len(s) else None

    # ── Cognitive Ability baselines ──
    cog_baselines = {
        "iq":     median("iq"),
        "gtq":    median("gtq"),
        "tiki":   median("tiki"),
        "pauli":  median("pauli"),
        "faxtor": median("faxtor"),
    }

    # ── Work Preferences baselines — all 20 PAPI scales ──
    papi_baselines = {
        code: median(code)
        for code, _, _ in _PAPI_SCALES
        if code in emp.columns
    }

    # ── Competency Execution baselines ──
    latest_year = int(comp_yearly["year"].max())
    comp_bench  = comp_yearly[
        comp_yearly["employee_id"].isin(bench_ids) &
        (comp_yearly["year"] == latest_year)
    ]
    comp_baselines = comp_bench.groupby("pillar_code")["score"].median().to_dict()

    # ── Behavioral Strengths baselines ──
    # DISC: majority type among benchmarks (categorical mode)
    bench_disc   = bench_df["disc"].dropna()
    disc_baseline = str(bench_disc.mode().iloc[0]) if len(bench_disc) else None

    # MBTI: majority valid type among benchmarks
    bench_mbti_raw   = bench_df["mbti"].dropna().str.strip().str.upper()
    bench_mbti_valid = bench_mbti_raw[bench_mbti_raw.isin(_VALID_MBTI)]
    mbti_baseline    = str(bench_mbti_valid.mode().iloc[0]) if len(bench_mbti_valid) else None

    # CliftonStrengths: pooled top-5 theme set across all benchmark employees
    bench_str_top5  = strengths[strengths["employee_id"].isin(bench_ids) & (strengths["rank"] <= 5)]
    bench_theme_pool = set(bench_str_top5["theme"].dropna().unique())

    # Precompute per-employee top-5 strengths dict for fast lookup
    emp_str_dict = (
        strengths[strengths["rank"] <= 5]
        .groupby("employee_id")["theme"]
        .apply(lambda x: set(x.dropna()))
        .to_dict()
    )

    # ── Contextual Fit baseline ──
    ctx_baseline = median("years_of_service_months")

    # --- match rate helpers ---
    def match_rate(user_val, base_val, inverse=False):
        """Numeric TV match rate. Returns None for missing data (not penalized as 0)."""
        try:
            if base_val is None or base_val == 0 or pd.isna(base_val):
                return None
            if user_val is None or pd.isna(user_val):
                return None
            if inverse:
                rate = (2 * base_val - float(user_val)) / base_val * 100
            else:
                rate = float(user_val) / base_val * 100
            return round(min(max(rate, 0.0), 100.0), 2)
        except Exception:
            return None

    def add_row(eid, emp_row, tgv, tv, base, user, inv=False, mr=_UNSET):
        """Append one TV row. Pass mr= to override numeric calculation (e.g. categorical)."""
        computed_mr = match_rate(user, base, inv) if mr is _UNSET else mr
        rows.append({
            "employee_id":    eid,
            "fullname":       emp_row.get("fullname"),
            "directorate":    emp_row.get("directorate"),
            "role":           emp_row.get("role"),
            "grade":          emp_row.get("grade"),
            "job_vacancy_id": vacancy_id,
            "tgv_name":       tgv,
            "tv_name":        tv,
            "baseline_score": base,
            "user_score":     user,
            "tv_match_rate":  computed_mr,
        })

    # --- build long-format TV rows ---
    rows = []

    for _, r in emp.iterrows():
        eid = r["employee_id"]

        # ── Cognitive Ability (5 TVs) ──
        add_row(eid, r, "Cognitive Ability", "IQ Score",     cog_baselines["iq"],     r.get("iq"))
        add_row(eid, r, "Cognitive Ability", "GTQ Score",    cog_baselines["gtq"],    r.get("gtq"))
        add_row(eid, r, "Cognitive Ability", "TIKI Score",   cog_baselines["tiki"],   r.get("tiki"))
        add_row(eid, r, "Cognitive Ability", "Pauli Score",  cog_baselines["pauli"],  r.get("pauli"))
        add_row(eid, r, "Cognitive Ability", "Faxtor Score", cog_baselines["faxtor"], r.get("faxtor"))

        # ── Work Preferences (all 20 PAPI scales) ──
        for code, label, is_inv in _PAPI_SCALES:
            add_row(eid, r, "Work Preferences", f"PAPI {label}",
                    papi_baselines.get(code), r.get(code), inv=is_inv)

        # ── Behavioral Strengths (3 TVs) ──
        # DISC — categorical: exact type match = 100%, mismatch = 0%
        emp_disc = r.get("disc")
        disc_mr  = None
        if disc_baseline is not None and emp_disc is not None:
            try:
                disc_mr = 100.0 if str(emp_disc).strip() == disc_baseline.strip() else 0.0
            except Exception:
                disc_mr = None
        add_row(eid, r, "Behavioral Strengths", "DISC Type",
                disc_baseline, emp_disc, mr=disc_mr)

        # MBTI — categorical: exact 4-letter type match = 100%, mismatch = 0%
        emp_mbti_raw = r.get("mbti")
        emp_mbti     = str(emp_mbti_raw or "").strip().upper()
        mbti_mr      = None
        if mbti_baseline is not None and emp_mbti in _VALID_MBTI:
            mbti_mr = 100.0 if emp_mbti == mbti_baseline else 0.0
        add_row(eid, r, "Behavioral Strengths", "MBTI Type",
                mbti_baseline, emp_mbti_raw, mr=mbti_mr)

        # CliftonStrengths — % of candidate's top-5 themes in benchmark pool
        cs_mr = None
        if bench_theme_pool:
            emp_themes = emp_str_dict.get(eid, set())
            overlap    = len(emp_themes & bench_theme_pool)
            cs_mr      = round(overlap / 5 * 100, 2)
            add_row(eid, r, "Behavioral Strengths", "CliftonStrengths Overlap",
                    len(bench_theme_pool), overlap, mr=cs_mr)
        else:
            add_row(eid, r, "Behavioral Strengths", "CliftonStrengths Overlap",
                    None, None, mr=None)

        # ── Contextual Fit (1 TV) ──
        add_row(eid, r, "Contextual Fit", "Years of Service",
                ctx_baseline, r.get("years_of_service_months"))

    df = pd.DataFrame(rows)

    # ── Competency Execution rows (1 row per employee × pillar, latest year) ──
    comp_emp_map = emp.set_index("employee_id").to_dict("index")
    comp_rows = []
    for _, cr in comp_yearly[comp_yearly["year"] == latest_year].iterrows():
        er = comp_emp_map.get(cr["employee_id"])
        if er is None:
            continue
        base_c = comp_baselines.get(cr["pillar_code"])
        mr     = match_rate(cr["score"], base_c)
        comp_rows.append({
            "employee_id":    cr["employee_id"],
            "fullname":       er.get("fullname"),
            "directorate":    er.get("directorate"),
            "role":           er.get("role"),
            "grade":          er.get("grade"),
            "job_vacancy_id": vacancy_id,
            "tgv_name":       "Competency Execution",
            "tv_name":        f"Pillar {cr['pillar_code']}",
            "baseline_score": base_c,
            "user_score":     float(cr["score"]),
            "tv_match_rate":  mr,
        })

    df = pd.concat([df, pd.DataFrame(comp_rows)], ignore_index=True)

    # --- TGV match rates (mean of TVs, NaN skipped automatically) ---
    tgv_df = (
        df.groupby(["employee_id", "job_vacancy_id", "tgv_name"])["tv_match_rate"]
          .mean()
          .reset_index()
          .rename(columns={"tv_match_rate": "tgv_match_rate"})
    )
    tgv_df["tgv_match_rate"] = tgv_df["tgv_match_rate"].round(2)

    # --- Final match rate: weighted avg of TGVs (weights sum = 1.0) ---
    tgv_df["weight"] = tgv_df["tgv_name"].map(tgv_weights).fillna(0.20)
    final_df = (
        tgv_df.groupby(["employee_id", "job_vacancy_id"])
              .apply(lambda g: round(
                  (g["tgv_match_rate"] * g["weight"]).sum() / g["weight"].sum(), 2
              ))
              .reset_index(name="final_match_rate")
    )

    # --- join back ---
    result = (
        df.merge(tgv_df[["employee_id", "tgv_name", "tgv_match_rate"]],
                 on=["employee_id", "tgv_name"], how="left")
          .merge(final_df[["employee_id", "final_match_rate"]],
                 on="employee_id", how="left")
    )
    return result.sort_values("final_match_rate", ascending=False).reset_index(drop=True)
