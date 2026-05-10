import os
import sys
sys.path.insert(0, os.path.dirname(__file__))

import streamlit as st
import pandas as pd
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

import matching as m
import ai_profile as ai
import charts as ch

# ── Page config ───────────────────────────────────────────────
st.set_page_config(
    page_title="Talent Match Intelligence",
    page_icon="🎯",
    layout="wide",
)

st.title("🎯 Talent Match Intelligence")
st.caption("AI-powered succession & talent matching system")

# ── Sidebar: Input Form ───────────────────────────────────────
with st.sidebar:
    st.header("1. Role Information")

    role_name = st.text_input("Role Name", placeholder="e.g. Marketing Manager")
    job_level = st.selectbox(
        "Job Level",
        ["", "Entry", "Junior", "Middle", "Senior", "Manager", "Director"],
    )
    role_purpose = st.text_area(
        "Role Purpose",
        placeholder="1–2 sentences describing the role outcome",
        height=100,
    )

    st.header("2. Employee Benchmarking")
    st.caption("Select up to 3 Rating-5 employees as benchmark.")

    @st.cache_data(ttl=300)
    def load_r5():
        return m.get_rating5_employees()

    r5 = load_r5()
    r5["label"] = r5["fullname"] + " (" + r5["employee_id"].astype(str) + ")"
    options = r5["label"].tolist()

    selected_labels = st.multiselect(
        "Choose benchmark employees (max 3)",
        options=options,
        max_selections=3,
    )
    selected_ids = [
        r5.loc[r5["label"] == lbl, "employee_id"].values[0]
        for lbl in selected_labels
    ]

    st.divider()
    run = st.button("✨ Generate Job Profile & Match Scores", use_container_width=True, type="primary")

# ── Main area: tabs ───────────────────────────────────────────
tab1, tab2, tab3, tab4 = st.tabs(["📋 Job Profile", "🏆 Ranked Talent", "📊 Dashboard", "🔍 Candidate Detail"])

# ── Session state ─────────────────────────────────────────────
if "result_df" not in st.session_state:
    st.session_state.result_df  = None
if "job_profile" not in st.session_state:
    st.session_state.job_profile = None
if "vacancy_id" not in st.session_state:
    st.session_state.vacancy_id  = None

# ── On submit ─────────────────────────────────────────────────
if run:
    if not role_name:
        st.error("Please enter a Role Name.")
    elif not job_level:
        st.error("Please select a Job Level.")
    elif len(selected_ids) == 0:
        st.error("Select at least 1 benchmark employee.")
    else:
        with st.spinner("Saving vacancy & computing match scores..."):
            vid = m.upsert_vacancy(role_name, job_level, role_purpose, selected_ids)
            result_df = m.compute_match(vid)
            st.session_state.vacancy_id  = vid
            st.session_state.result_df   = result_df

        with st.spinner("Generating AI job profile..."):
            tgv_avgs = (
                result_df[result_df["employee_id"].isin(selected_ids)]
                .drop_duplicates(["employee_id","tgv_name"])
                .groupby("tgv_name")["tgv_match_rate"].mean()
                .round(1).to_dict()
            )
            # placeholder strengths — replace with real top themes after exploration
            top_themes = ["Achiever", "Analytical", "Learner", "Strategic", "Responsibility"]

            profile = ai.generate_job_profile(
                role_name, job_level, role_purpose, tgv_avgs, top_themes
            )
            st.session_state.job_profile = profile

        st.success(f"Done! Vacancy ID: `{vid}`")

# ── TAB 1: Job Profile ────────────────────────────────────────
with tab1:
    if st.session_state.job_profile:
        p = st.session_state.job_profile
        st.subheader(f"Role: {role_name}  |  Level: {job_level}")
        st.markdown(f"**Role Purpose:** {role_purpose}")
        st.divider()

        col1, col2 = st.columns(2)
        with col1:
            st.markdown("#### Job Requirements")
            for req in p.get("job_requirements", []):
                st.markdown(f"- {req}")

            st.markdown("#### Key Competencies")
            for comp in p.get("key_competencies", []):
                st.markdown(f"- {comp}")

        with col2:
            st.markdown("#### Job Description")
            st.info(p.get("job_description", ""))

            st.markdown("#### Benchmark Employees")
            if selected_ids:
                for eid in selected_ids:
                    row = r5[r5["employee_id"] == eid]
                    if not row.empty:
                        st.write(f"- {row['fullname'].values[0]} `({eid})`")
    else:
        st.info("Fill in the form on the left and click **Generate** to create a job profile.")

# ── TAB 2: Ranked Talent ──────────────────────────────────────
with tab2:
    if st.session_state.result_df is not None:
        df = st.session_state.result_df
        ranked = (
            df.drop_duplicates("employee_id")
              [["employee_id","fullname","directorate","role","grade","final_match_rate"]]
              .sort_values("final_match_rate", ascending=False)
              .reset_index(drop=True)
        )
        ranked.index += 1

        search = st.text_input("Search by name, role, or directorate")
        if search:
            mask = ranked.apply(lambda r: search.lower() in r.to_string().lower(), axis=1)
            ranked = ranked[mask]

        st.dataframe(
            ranked.style.background_gradient(subset=["final_match_rate"], cmap="Blues"),
            use_container_width=True,
        )
        st.caption(f"Showing {len(ranked)} candidates · Vacancy: `{st.session_state.vacancy_id}`")
    else:
        st.info("Generate match scores first.")

# ── TAB 3: Dashboard ──────────────────────────────────────────
with tab3:
    if st.session_state.result_df is not None:
        df = st.session_state.result_df

        col1, col2 = st.columns(2)
        with col1:
            st.plotly_chart(ch.match_distribution(df), use_container_width=True)
        with col2:
            st.plotly_chart(ch.ranked_bar(df, top_n=15), use_container_width=True)

        st.plotly_chart(ch.tgv_heatmap(df, top_n=20), use_container_width=True)
    else:
        st.info("Generate match scores first.")

# ── TAB 4: Candidate Detail ───────────────────────────────────
with tab4:
    if st.session_state.result_df is not None:
        df = st.session_state.result_df
        ranked_ids = (
            df.drop_duplicates("employee_id")
              .sort_values("final_match_rate", ascending=False)["employee_id"]
              .tolist()
        )
        names = df.drop_duplicates("employee_id").set_index("employee_id")["fullname"].to_dict()
        options_detail = [f"{names[eid]} ({eid})" for eid in ranked_ids[:50]]

        selected_detail = st.selectbox("Select candidate", options=options_detail)
        if selected_detail:
            cand_id = selected_detail.split("(")[-1].rstrip(")")

            row = df[df["employee_id"] == cand_id].drop_duplicates("employee_id").iloc[0]
            c1, c2, c3, c4 = st.columns(4)
            c1.metric("Final Match Rate", f"{row['final_match_rate']:.1f}%")
            c2.metric("Directorate", row["directorate"] or "—")
            c3.metric("Role", row["role"] or "—")
            c4.metric("Grade", row["grade"] or "—")

            col_r, col_b = st.columns(2)
            with col_r:
                st.plotly_chart(ch.radar_benchmark_vs_candidate(df, cand_id), use_container_width=True)
            with col_b:
                st.plotly_chart(ch.top_strengths_gaps(df, cand_id), use_container_width=True)

            st.markdown("#### TV-Level Detail")
            detail = (
                df[df["employee_id"] == cand_id]
                [["tgv_name","tv_name","baseline_score","user_score","tv_match_rate","tgv_match_rate"]]
                .drop_duplicates()
                .sort_values(["tgv_name","tv_match_rate"], ascending=[True,False])
                .reset_index(drop=True)
            )
            st.dataframe(
                detail.style.background_gradient(subset=["tv_match_rate"], cmap="RdYlGn"),
                use_container_width=True,
            )
    else:
        st.info("Generate match scores first.")
