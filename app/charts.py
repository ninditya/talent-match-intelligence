import pandas as pd
import plotly.express as px
import plotly.graph_objects as go


BRAND_COLORS = px.colors.sequential.Blues_r


def match_distribution(result_df: pd.DataFrame) -> go.Figure:
    """Histogram of final_match_rate across all candidates."""
    ranked = result_df.drop_duplicates("employee_id")
    fig = px.histogram(
        ranked, x="final_match_rate", nbins=20,
        title="Match Rate Distribution — All Candidates",
        labels={"final_match_rate": "Final Match Rate (%)"},
        color_discrete_sequence=[BRAND_COLORS[2]],
    )
    fig.update_layout(bargap=0.05)
    return fig


def tgv_heatmap(result_df: pd.DataFrame, top_n: int = 20) -> go.Figure:
    """Heatmap: top N candidates × TGV match rates."""
    top_ids = (
        result_df.drop_duplicates("employee_id")
                 .nlargest(top_n, "final_match_rate")["employee_id"]
    )
    pivot = (
        result_df[result_df["employee_id"].isin(top_ids)]
        .drop_duplicates(["employee_id","tgv_name"])
        .pivot(index="fullname", columns="tgv_name", values="tgv_match_rate")
    )
    fig = px.imshow(
        pivot,
        title=f"TGV Match Rates — Top {top_n} Candidates",
        labels={"color": "Match Rate (%)"},
        color_continuous_scale="Blues",
        zmin=0, zmax=100,
        aspect="auto",
    )
    return fig


def radar_benchmark_vs_candidate(
    result_df: pd.DataFrame,
    candidate_id: str,
) -> go.Figure:
    """Radar chart comparing a candidate's TGV rates vs benchmark average."""
    cand = (
        result_df[result_df["employee_id"] == candidate_id]
        .drop_duplicates("tgv_name")[["tgv_name","tgv_match_rate"]]
        .set_index("tgv_name")
    )

    categories = cand.index.tolist()
    cand_vals  = cand["tgv_match_rate"].tolist()
    bench_vals = [100.0] * len(categories)   # benchmark = 100% by definition

    fig = go.Figure()
    fig.add_trace(go.Scatterpolar(
        r=cand_vals + [cand_vals[0]],
        theta=categories + [categories[0]],
        fill="toself", name="Candidate",
        line_color=BRAND_COLORS[1],
    ))
    fig.add_trace(go.Scatterpolar(
        r=bench_vals + [bench_vals[0]],
        theta=categories + [categories[0]],
        fill="toself", name="Benchmark",
        line_color="rgba(180,180,180,0.6)",
        fillcolor="rgba(180,180,180,0.15)",
    ))
    name = result_df[result_df["employee_id"] == candidate_id]["fullname"].iloc[0]
    fig.update_layout(
        title=f"TGV Radar — {name}",
        polar=dict(radialaxis=dict(visible=True, range=[0, 100])),
    )
    return fig


def top_strengths_gaps(result_df: pd.DataFrame, candidate_id: str) -> go.Figure:
    """Horizontal bar: TV match rates for a single candidate, sorted."""
    cand = result_df[result_df["employee_id"] == candidate_id].copy()
    cand = cand.drop_duplicates(["tgv_name","tv_name"]).dropna(subset=["tv_match_rate"])
    cand = cand.sort_values("tv_match_rate")

    fig = px.bar(
        cand, x="tv_match_rate", y="tv_name",
        color="tgv_name", orientation="h",
        title="TV Match Rates — Strengths & Gaps",
        labels={"tv_match_rate": "Match Rate (%)", "tv_name": "Talent Variable"},
    )
    fig.add_vline(x=80, line_dash="dash", line_color="green",
                  annotation_text="80% threshold")
    return fig


def ranked_bar(result_df: pd.DataFrame, top_n: int = 15) -> go.Figure:
    """Bar chart of top N candidates by final_match_rate."""
    ranked = (
        result_df.drop_duplicates("employee_id")
                 .nlargest(top_n, "final_match_rate")
                 .sort_values("final_match_rate")
    )
    fig = px.bar(
        ranked, x="final_match_rate", y="fullname",
        orientation="h",
        title=f"Top {top_n} Candidates by Final Match Rate",
        labels={"final_match_rate": "Final Match Rate (%)", "fullname": "Employee"},
        color="final_match_rate", color_continuous_scale="Blues",
        range_color=[ranked["final_match_rate"].min() - 5, 100],
    )
    return fig
