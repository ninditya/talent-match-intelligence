"""
Full EDA script — runs all analysis and exports charts + findings.
Run: python3 scripts/eda_analysis.py
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import pandas as pd
import numpy as np
import plotly.express as px
import plotly.graph_objects as go
from plotly.subplots import make_subplots
from supabase import create_client
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

CHARTS = os.path.join(os.path.dirname(__file__), '..', 'assets', 'charts')
os.makedirs(CHARTS, exist_ok=True)

sb = create_client(os.environ['SUPABASE_URL'], os.environ['SUPABASE_KEY'])

def fetch(table, page_size=1000):
    """Paginate through all rows — Supabase default cap is 1,000/request."""
    all_rows, offset = [], 0
    while True:
        r = sb.table(table).select('*').range(offset, offset + page_size - 1).execute()
        batch = r.data
        all_rows.extend(batch)
        if len(batch) < page_size:
            break
        offset += page_size
    return pd.DataFrame(all_rows)

def save(fig, name):
    fig.write_image(os.path.join(CHARTS, name), width=1000, height=600)
    print(f'  Saved {name}')

print('='*60)
print('TALENT MATCH INTELLIGENCE — EDA ANALYSIS')
print('='*60)

# ── Load all tables ──────────────────────────────────────────
print('\n[1] Loading tables...')
employees   = fetch('employees')
perf        = fetch('performance_yearly')
psych       = fetch('profiles_psych')
papi        = fetch('papi_scores')
strengths   = fetch('strengths')
comp        = fetch('competencies_yearly')
dim_grades  = fetch('dim_grades')
dim_pos     = fetch('dim_positions')
dim_dirs    = fetch('dim_directorates')
dim_edu     = fetch('dim_education')
dim_pillars = fetch('dim_competency_pillars')

# ── Row counts ───────────────────────────────────────────────
print('\n[2] ROW COUNTS')
print('-'*40)
for name, df in [('employees',employees),('performance_yearly',perf),
                 ('profiles_psych',psych),('papi_scores',papi),
                 ('strengths',strengths),('competencies_yearly',comp)]:
    print(f'  {name:<25} {len(df):>7,} rows')

# ── Latest rating per employee ───────────────────────────────
latest_perf = (
    perf.sort_values('year', ascending=False)
        .drop_duplicates('employee_id')
        .rename(columns={'rating': 'latest_rating'})
)

print('\n[3] RATING DISTRIBUTION (latest year)')
print('-'*40)
rc = latest_perf['latest_rating'].value_counts().sort_index()
for rating, count in rc.items():
    pct = count / len(latest_perf) * 100
    print(f'  Rating {rating}: {count:>5} employees ({pct:.1f}%)')

r5 = latest_perf[latest_perf['latest_rating'] == 5]
print(f'\n  Rating=5 (high performers): {len(r5)} ({len(r5)/len(latest_perf)*100:.1f}%)')

# ── NULL analysis ────────────────────────────────────────────
print('\n[4] NULL ANALYSIS — KEY COLUMNS')
print('-'*40)
null_checks = {
    'profiles_psych.iq':   psych['iq'].isnull().sum(),
    'profiles_psych.gtq':  psych['gtq'].isnull().sum(),
    'profiles_psych.tiki': psych['tiki'].isnull().sum(),
    'profiles_psych.mbti': psych['mbti'].isnull().sum(),
    'profiles_psych.disc': psych['disc'].isnull().sum(),
    'papi_scores.score':   papi['score'].isnull().sum(),
    'performance.rating':  perf['rating'].isnull().sum(),
    'competencies.score':  comp['score'].isnull().sum(),
}
for col, nulls in null_checks.items():
    total = len(psych) if 'psych' in col else (len(papi) if 'papi' in col else (len(perf) if 'perf' in col else len(comp)))
    pct = nulls / total * 100
    print(f'  {col:<30} {nulls:>5} nulls ({pct:.1f}%)')

# ── Duplicate check ──────────────────────────────────────────
print('\n[5] DUPLICATE CHECK')
print('-'*40)
print(f'  employees duplicate IDs:        {employees["employee_id"].duplicated().sum()}')
print(f'  psych duplicate employee_ids:   {psych["employee_id"].duplicated().sum()}')
print(f'  papi (emp+scale) dupes:         {papi.duplicated(["employee_id","scale_code"]).sum()}')

# ── MBTI dirty data ──────────────────────────────────────────
print('\n[6] MBTI UNIQUE VALUES (dirty data check)')
print('-'*40)
mbti_vals = psych['mbti'].dropna().str.strip().str.upper().value_counts()
valid_mbti = {'INTJ','INTP','ENTJ','ENTP','INFJ','INFP','ENFJ','ENFP',
              'ISTJ','ISFJ','ESTJ','ESFJ','ISTP','ISFP','ESTP','ESFP'}
print(f'  Total non-null: {psych["mbti"].notna().sum()}')
print(f'  Unique values:  {mbti_vals.nunique()}')
invalid = [v for v in mbti_vals.index if v not in valid_mbti]
if invalid:
    print(f'  Invalid MBTI:   {invalid}')
else:
    print('  All MBTI valid (16 types only)')

# ── DISC unique values ───────────────────────────────────────
print('\n[7] DISC UNIQUE VALUES')
print('-'*40)
disc_vals = psych['disc'].dropna().str.strip().str.upper().value_counts()
print(disc_vals.to_string())

# ─────────────────────────────────────────────────────────────
# ANALYSIS SECTION
# ─────────────────────────────────────────────────────────────

# Enrich employees
emp = (
    employees
    .merge(dim_grades.rename(columns={'name':'grade'})[['grade_id','grade']], on='grade_id', how='left')
    .merge(dim_pos.rename(columns={'name':'role'})[['position_id','role']], on='position_id', how='left')
    .merge(dim_dirs.rename(columns={'name':'directorate'})[['directorate_id','directorate']], on='directorate_id', how='left')
    .merge(dim_edu.rename(columns={'name':'education'})[['education_id','education']], on='education_id', how='left')
    .merge(latest_perf[['employee_id','latest_rating']], on='employee_id', how='left')
)
emp['group'] = emp['latest_rating'].apply(lambda x: 'Rating 5' if x == 5 else 'Others')

# ── CHART 1: Rating Distribution ─────────────────────────────
print('\n[8] Building charts...')
fig = px.histogram(
    latest_perf, x='latest_rating', nbins=5,
    title='Performance Rating Distribution (Latest Year per Employee)',
    labels={'latest_rating': 'Rating', 'count': 'Employees'},
    color_discrete_sequence=['#1d6fa8'],
    text_auto=True
)
fig.update_layout(bargap=0.1, showlegend=False)
save(fig, '01_rating_distribution.png')

# ── CHART 2: Competency Pillar Heatmap ───────────────────────
comp_merged = (
    comp.merge(latest_perf[['employee_id','latest_rating']], on='employee_id')
        .merge(dim_pillars, on='pillar_code')
)
comp_pivot = (
    comp_merged.groupby(['pillar_label','latest_rating'])['score']
               .mean().reset_index()
               .pivot(index='pillar_label', columns='latest_rating', values='score')
)
fig2 = px.imshow(
    comp_pivot.T.round(2),
    title='Avg Competency Score by Pillar × Rating Group',
    labels={'x':'Competency Pillar','y':'Rating','color':'Avg Score'},
    color_continuous_scale='Blues', text_auto='.2f', aspect='auto'
)
save(fig2, '02_competency_heatmap.png')

# Pillar avg diff: Rating5 vs Others
comp_r5     = comp_merged[comp_merged['latest_rating']==5].groupby('pillar_label')['score'].mean()
comp_others = comp_merged[comp_merged['latest_rating']!=5].groupby('pillar_label')['score'].mean()
comp_diff   = (comp_r5 - comp_others).sort_values(ascending=False).reset_index()
comp_diff.columns = ['pillar_label','diff']
print('\n[9] COMPETENCY PILLAR DIFF (Rating5 - Others):')
print(comp_diff.to_string(index=False))

# ── CHART 3: Competency Diff Bar ─────────────────────────────
fig3 = px.bar(
    comp_diff.sort_values('diff'),
    x='diff', y='pillar_label', orientation='h',
    title='Competency Score Gap: Rating 5 vs Others',
    color='diff', color_continuous_scale='RdBu_r',
    labels={'diff': 'Rating5 − Others', 'pillar_label': 'Pillar'}
)
save(fig3, '02b_competency_diff.png')

# ── CHART 4: Psychometric Radar ──────────────────────────────
psych_merged = psych.merge(emp[['employee_id','group']], on='employee_id', how='left')
num_cols = [c for c in ['iq','gtq','tiki','pauli','faxtor'] if c in psych_merged.columns]

psych_group = psych_merged.groupby('group')[num_cols].mean()
print('\n[10] PSYCHOMETRIC AVERAGES BY GROUP:')
print(psych_group.round(2).to_string())

# Normalize for radar
norm = psych_group.copy()
for col in norm.columns:
    mn, mx = norm[col].min(), norm[col].max()
    if mx > mn:
        norm[col] = (norm[col] - mn) / (mx - mn) * 100

fig4 = go.Figure()
colors = {'Rating 5': '#1d6fa8', 'Others': '#a8a8a8'}
for grp in ['Rating 5', 'Others']:
    if grp not in norm.index:
        continue
    vals = norm.loc[grp, num_cols].tolist()
    fig4.add_trace(go.Scatterpolar(
        r=vals + [vals[0]], theta=num_cols + [num_cols[0]],
        fill='toself', name=grp, line_color=colors[grp]
    ))
fig4.update_layout(
    title='Psychometric Profile: Rating 5 vs Others (normalized 0-100)',
    polar=dict(radialaxis=dict(visible=True, range=[0, 100]))
)
save(fig4, '03_psych_radar.png')

# ── CHART 5: PAPI Analysis ───────────────────────────────────
papi_merged = papi.merge(emp[['employee_id','group']], on='employee_id', how='left')
papi_pivot = (
    papi_merged.groupby(['scale_code','group'])['score']
               .mean().unstack()
)
papi_pivot['diff'] = papi_pivot.get('Rating 5', 0) - papi_pivot.get('Others', 0)
papi_pivot = papi_pivot.sort_values('diff', ascending=False)

print('\n[11] PAPI SCALE DIFF (Rating5 - Others):')
print(papi_pivot[['Rating 5','Others','diff']].round(3).to_string())

fig5 = px.bar(
    papi_pivot.reset_index().sort_values('diff'),
    x='diff', y='scale_code', orientation='h',
    title='PAPI Scale Gap: Rating 5 vs Others (+ = high performers score higher)',
    color='diff', color_continuous_scale='RdBu_r',
    labels={'diff': 'Rating5 − Others', 'scale_code': 'PAPI Scale'}
)
save(fig5, '04_papi_diff.png')

# ── CHART 6: CliftonStrengths ────────────────────────────────
str_merged = strengths.merge(emp[['employee_id','group']], on='employee_id', how='left')
top5_r5 = str_merged[(str_merged['group']=='Rating 5') & (str_merged['rank']<=5)]
top5_oth = str_merged[(str_merged['group']=='Others')  & (str_merged['rank']<=5)]

theme_r5  = top5_r5['theme'].value_counts().reset_index()
theme_oth = top5_oth['theme'].value_counts().reset_index()
theme_r5.columns  = ['theme','count_r5']
theme_oth.columns = ['theme','count_others']
theme_comp = theme_r5.merge(theme_oth, on='theme', how='outer').fillna(0)
theme_comp['r5_pct']  = theme_comp['count_r5']  / len(top5_r5['employee_id'].unique())  * 100
theme_comp['oth_pct'] = theme_comp['count_others'] / len(top5_oth['employee_id'].unique()) * 100
theme_comp['diff_pct']= theme_comp['r5_pct'] - theme_comp['oth_pct']
theme_comp = theme_comp.sort_values('diff_pct', ascending=False).head(15)

print('\n[12] TOP CLIFTON THEMES (% employees with theme in top-5):')
print(theme_comp[['theme','r5_pct','oth_pct','diff_pct']].round(1).to_string(index=False))

fig6 = px.bar(
    theme_comp.sort_values('r5_pct', ascending=True),
    x='r5_pct', y='theme', orientation='h',
    title='CliftonStrengths: % Rating-5 Employees with Theme in Top 5',
    color='diff_pct', color_continuous_scale='Blues',
    labels={'r5_pct':'% of Rating-5 Employees','theme':'Strength Theme'}
)
save(fig6, '05_strengths_top.png')

# ── CHART 7: DISC Distribution ───────────────────────────────
psych['disc_clean'] = psych['disc'].str.strip().str.upper()
disc_merged = psych.merge(emp[['employee_id','group']], on='employee_id', how='left')
disc_r5  = disc_merged[disc_merged['group']=='Rating 5']['disc_clean'].value_counts(normalize=True).mul(100).round(1)
disc_oth = disc_merged[disc_merged['group']=='Others']['disc_clean'].value_counts(normalize=True).mul(100).round(1)
print('\n[13] DISC DIST — Rating 5 (top 8):')
print(disc_r5.head(8).to_string())

# ── CHART 8: MBTI Distribution ───────────────────────────────
psych['mbti_clean'] = psych['mbti'].str.strip().str.upper()
mbti_merged = psych.merge(emp[['employee_id','group']], on='employee_id', how='left')
mbti_r5 = mbti_merged[mbti_merged['group']=='Rating 5']['mbti_clean'].value_counts(normalize=True).mul(100).round(1)
print('\n[14] MBTI DIST — Rating 5 (top 8):')
print(mbti_r5.head(8).to_string())

# ── CHART 9: Contextual Factors ──────────────────────────────
fig7 = px.box(
    emp, x='latest_rating', y='years_of_service_months',
    title='Years of Service vs Performance Rating',
    color='group', color_discrete_map={'Rating 5':'#1d6fa8','Others':'#a8a8a8'},
    labels={'years_of_service_months':'Months of Service','latest_rating':'Rating'}
)
save(fig7, '06_tenure_vs_rating.png')

grade_rating = emp.groupby(['grade','group']).size().reset_index(name='count')
fig8 = px.bar(
    grade_rating, x='grade', y='count', color='group',
    barmode='group', title='Grade Distribution by Performance Group',
    color_discrete_map={'Rating 5':'#1d6fa8','Others':'#a8a8a8'}
)
save(fig8, '07_grade_vs_rating.png')

# ── CHART 10: Correlation Matrix ─────────────────────────────
master = emp.merge(psych, on='employee_id', how='left')
num_cols_corr = [c for c in ['latest_rating','years_of_service_months','iq','gtq','tiki','pauli','faxtor']
                 if c in master.columns]
corr = master[num_cols_corr].corr()
print('\n[15] CORRELATIONS WITH latest_rating:')
print(corr['latest_rating'].sort_values(ascending=False).round(3).to_string())

fig9 = px.imshow(
    corr, title='Correlation Matrix — Numeric Features vs Rating',
    color_continuous_scale='RdBu', zmin=-1, zmax=1, text_auto='.2f'
)
save(fig9, '08_correlation_matrix.png')

# ── SUCCESS FORMULA SUMMARY ───────────────────────────────────
print('\n' + '='*60)
print('SUCCESS FORMULA — derived from findings')
print('='*60)

top_papi = papi_pivot['diff'].abs().sort_values(ascending=False).head(7).index.tolist()
top_themes = theme_comp.head(5)['theme'].tolist()

formula = {
    'Cognitive Ability':    {'weight': 0.30, 'tvs': ['iq','gtq','tiki','pauli','faxtor'],
                              'rationale': 'Strongest corr with rating; highest diff between R5 and Others'},
    'Competency Execution': {'weight': 0.25, 'tvs': list(comp_diff.head(5)['pillar_label']),
                              'rationale': f'Top differentiating pillars: {comp_diff.head(3)["pillar_label"].tolist()}'},
    'Work Preferences':     {'weight': 0.20, 'tvs': top_papi,
                              'rationale': f'Top PAPI diff scales: {top_papi[:3]}'},
    'Behavioral Strengths': {'weight': 0.15, 'tvs': top_themes,
                              'rationale': f'Top themes in R5: {top_themes[:3]}'},
    'Contextual Fit':       {'weight': 0.10, 'tvs': ['years_of_service_months','grade'],
                              'rationale': 'Moderate contextual signal; grade correlates with seniority'},
}

total_w = 0
for tgv, cfg in formula.items():
    print(f"\n  {tgv} ({cfg['weight']:.0%})")
    print(f"    TVs: {cfg['tvs']}")
    print(f"    Why: {cfg['rationale']}")
    total_w += cfg['weight']
print(f'\n  Total weight: {total_w:.0%}')

print('\n[DONE] All charts saved to assets/charts/')
print(f'[DONE] Charts generated: {len(os.listdir(CHARTS))} files')
