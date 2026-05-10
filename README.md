# Talent Match Intelligence

AI-powered succession and talent matching system built for the Data Analyst Case Study 2025.

## What It Does

1. **Success Pattern Discovery** — analyzes what differentiates Rating-5 employees across competencies, psychometrics, PAPI work preferences, CliftonStrengths, and contextual factors.
2. **SQL Matching Algorithm** — computes how closely every employee matches a benchmark profile using a weighted TV → TGV → Final Match Rate pipeline.
3. **AI Talent App** — Streamlit dashboard that generates job profiles via LLM and visualizes match scores interactively.

## Project Structure

```
talent-match-intelligence/
├── app/
│   ├── main.py           # Streamlit app (entry point)
│   ├── matching.py       # Matching algorithm (Python mirror of SQL logic)
│   ├── ai_profile.py     # LLM job profile generation via OpenRouter
│   ├── charts.py         # Plotly chart builders
│   └── db.py             # Supabase client helper
├── notebooks/
│   └── 01_success_pattern.ipynb   # Step 1 EDA & Success Formula
├── sql/
│   └── matching_algorithm.sql     # Documented CTE-based matching query
├── assets/
│   └── charts/           # Exported chart PNGs for report
├── .streamlit/
│   ├── config.toml
│   └── secrets.toml.example
├── .env.example
├── requirements.txt
└── README.md
```

## Setup

### 1. Clone & Install

```bash
git clone https://github.com/YOUR_USERNAME/talent-match-intelligence
cd talent-match-intelligence
pip install -r requirements.txt
```

### 2. Configure Environment

```bash
cp .env.example .env
# Edit .env with your Supabase URL, key, and OpenRouter API key
```

### 3. Run the Streamlit App

```bash
streamlit run app/main.py
```

### 4. Run the Exploration Notebook

```bash
cd notebooks
jupyter notebook 01_success_pattern.ipynb
```

## Database Setup (Supabase)

Run the DDL in `sql/matching_algorithm.sql` (lines 1–45) once to create:
- `talent_benchmarks` — stores vacancy definitions
- `tv_definitions` — maps Talent Variables to data sources

## Deployment (Streamlit Cloud)

1. Push this repo to GitHub
2. Go to [share.streamlit.io](https://share.streamlit.io) → New app
3. Set **Main file path**: `app/main.py`
4. Add secrets in **Settings → Secrets** (copy from `.streamlit/secrets.toml.example`)

## Tech Stack

| Layer | Tool |
|-------|------|
| Database | Supabase (Postgres) |
| Analysis | Python, Pandas, Plotly |
| App | Streamlit |
| AI | OpenRouter (Llama 3.1 free tier) |
| Version Control | GitHub |
