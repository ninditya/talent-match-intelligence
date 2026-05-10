import os
import uuid
import pandas as pd
from supabase import create_client
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

_sb = None

def _client():
    global _sb
    if _sb is None:
        _sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])
    return _sb


def fetch_table(table: str, cols: str = "*", limit: int = 50000) -> pd.DataFrame:
    r = _client().table(table).select(cols).limit(limit).execute()
    return pd.DataFrame(r.data)


def get_all_employees() -> pd.DataFrame:
    """Return employee list with latest rating."""
    emps = fetch_table("employees", "employee_id,fullname")
    perf = fetch_table("performance_yearly")
    latest = (
        perf.sort_values("year", ascending=False)
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


def compute_match(vacancy_id: str) -> pd.DataFrame:
    """
    Run the matching algorithm in Python, aligned with actual ERD schema.
    profiles_psych columns: iq, gtq (int), tiki (int), pauli, faxtor, disc, disc_word, mbti
    Returns: full result DataFrame per case study brief.
    """
    # --- load tables ---
    employees   = fetch_table("employees")
    psych       = fetch_table("profiles_psych")
    papi_raw    = fetch_table("papi_scores")
    comp_yearly = fetch_table("competencies_yearly")
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

    # TGV weights (overridable via weights_config)
    tgv_weights = {
        "Cognitive Ability":    weights_cfg.get("Cognitive Ability",    0.30),
        "Work Preferences":     weights_cfg.get("Work Preferences",     0.20),
        "Competency Execution": weights_cfg.get("Competency Execution", 0.25),
        "Behavioral Strengths": weights_cfg.get("Behavioral Strengths", 0.15),
        "Contextual Fit":       weights_cfg.get("Contextual Fit",       0.10),
    }

    # --- pivot PAPI to wide format ---
    papi_wide = (
        papi_raw.pivot(index="employee_id", columns="scale_code", values="score")
                .reset_index()
    )

    # --- enrich employees with dim lookups + psych + papi ---
    emp = (
        employees
        .merge(dim_grades.rename(columns={"name": "grade"})[["grade_id","grade"]],
               on="grade_id", how="left")
        .merge(dim_pos.rename(columns={"name": "role"})[["position_id","role"]],
               on="position_id", how="left")
        .merge(dim_dirs.rename(columns={"name": "directorate"})[["directorate_id","directorate"]],
               on="directorate_id", how="left")
        .merge(psych, on="employee_id", how="left")
        .merge(papi_wide, on="employee_id", how="left")
    )

    # --- compute benchmark medians ---
    bench_df = emp[emp["employee_id"].isin(bench_ids)]

    def median(col):
        if col not in bench_df.columns:
            return None
        s = bench_df[col].dropna()
        return float(s.median()) if len(s) else None

    # Cognitive Ability TVs — using actual ERD columns: iq, gtq, tiki, pauli, faxtor
    cog_baselines = {
        "iq":    median("iq"),
        "gtq":   median("gtq"),
        "tiki":  median("tiki"),
        "pauli": median("pauli"),
        "faxtor":median("faxtor"),
    }

    # Work Preferences PAPI
    papi_scales    = ["Papi_N","Papi_G","Papi_A","Papi_L","Papi_P",
                      "Papi_Z","Papi_K","Papi_I","Papi_T","Papi_V"]
    inverse_scales = {"Papi_Z", "Papi_K"}
    papi_baselines = {s: median(s) for s in papi_scales if s in emp.columns}

    # Competency Execution — median per pillar (latest year)
    latest_year    = int(comp_yearly["year"].max())
    comp_bench     = comp_yearly[
        comp_yearly["employee_id"].isin(bench_ids) &
        (comp_yearly["year"] == latest_year)
    ]
    comp_baselines = comp_bench.groupby("pillar_code")["score"].median().to_dict()

    # Contextual Fit
    ctx_baseline = median("years_of_service_months")

    # --- TV match rate helper ---
    def match_rate(user_val, base_val, inverse=False):
        try:
            if base_val is None or base_val == 0 or pd.isna(base_val):
                return None
            if user_val is None or pd.isna(user_val):
                return 0.0
            if inverse:
                rate = (2 * base_val - float(user_val)) / base_val * 100
            else:
                rate = float(user_val) / base_val * 100
            return round(min(max(rate, 0.0), 100.0), 2)
        except Exception:
            return None

    # --- build long-format TV rows ---
    rows = []

    def add_row(eid, emp_row, tgv, tv, base, user, inv=False):
        mr = match_rate(user, base, inv)
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
            "tv_match_rate":  mr,
        })

    for _, r in emp.iterrows():
        eid = r["employee_id"]

        # — Cognitive Ability —
        add_row(eid, r, "Cognitive Ability", "IQ Score",     cog_baselines["iq"],     r.get("iq"))
        add_row(eid, r, "Cognitive Ability", "GTQ Score",    cog_baselines["gtq"],    r.get("gtq"))
        add_row(eid, r, "Cognitive Ability", "TIKI Score",   cog_baselines["tiki"],   r.get("tiki"))
        add_row(eid, r, "Cognitive Ability", "Pauli Score",  cog_baselines["pauli"],  r.get("pauli"))
        add_row(eid, r, "Cognitive Ability", "Faxtor Score", cog_baselines["faxtor"], r.get("faxtor"))

        # — Work Preferences (PAPI) —
        for scale, label in [
            ("Papi_N","Need for Achievement"), ("Papi_G","Leadership"),
            ("Papi_A","Attention to Detail"),  ("Papi_L","Work Pace"),
            ("Papi_P","Planning"),             ("Papi_Z","Avoidance of Change"),
            ("Papi_K","Conformity"),           ("Papi_I","Initiative"),
            ("Papi_T","Tenacity"),             ("Papi_V","Vigour"),
        ]:
            base_p = papi_baselines.get(scale)
            add_row(eid, r, "Work Preferences", f"PAPI {label}",
                    base_p, r.get(scale), inv=(scale in inverse_scales))

        # — Contextual Fit —
        add_row(eid, r, "Contextual Fit", "Years of Service",
                ctx_baseline, r.get("years_of_service_months"))

    df = pd.DataFrame(rows)

    # Add Competency Execution rows per pillar
    comp_rows = []
    for _, cr in comp_yearly[comp_yearly["year"] == latest_year].iterrows():
        base_c = comp_baselines.get(cr["pillar_code"])
        emp_info = emp[emp["employee_id"] == cr["employee_id"]]
        if emp_info.empty:
            continue
        er = emp_info.iloc[0]
        mr = match_rate(cr["score"], base_c)
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

    # --- TGV match rates (avg of TVs within TGV) ---
    tgv_df = (
        df.groupby(["employee_id","job_vacancy_id","tgv_name"])["tv_match_rate"]
          .mean().reset_index()
          .rename(columns={"tv_match_rate": "tgv_match_rate"})
    )
    tgv_df["tgv_match_rate"] = tgv_df["tgv_match_rate"].round(2)

    # --- Final match rate (weighted avg of TGVs) ---
    tgv_df["weight"] = tgv_df["tgv_name"].map(tgv_weights).fillna(0.20)
    final_df = (
        tgv_df.groupby(["employee_id","job_vacancy_id"])
              .apply(lambda g: round(
                  (g["tgv_match_rate"] * g["weight"]).sum() / g["weight"].sum(), 2
              ))
              .reset_index(name="final_match_rate")
    )

    # --- join back ---
    result = (
        df.merge(tgv_df[["employee_id","tgv_name","tgv_match_rate"]], on=["employee_id","tgv_name"], how="left")
          .merge(final_df[["employee_id","final_match_rate"]], on="employee_id", how="left")
    )
    return result.sort_values("final_match_rate", ascending=False).reset_index(drop=True)
