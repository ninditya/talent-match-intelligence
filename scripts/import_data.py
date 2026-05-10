"""
Import all sheets from Google Sheets into Supabase.
Run: python3 scripts/import_data.py
"""
import os, sys, io, time
import requests
import pandas as pd
from supabase import create_client
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

SHEET_ID   = '1BuOG4dbw8zy6z36W41qyhOblG3UkscPFSehcRQjOtC4'
BATCH_SIZE = 500   # rows per upsert call

sb = create_client(os.environ['SUPABASE_URL'], os.environ['SUPABASE_KEY'])

# Import order respects FK dependencies (dims before facts)
IMPORT_ORDER = [
    'dim_companies',
    'dim_areas',
    'dim_positions',
    'dim_departments',
    'dim_divisions',
    'dim_directorates',
    'dim_grades',
    'dim_education',
    'dim_majors',
    'dim_competency_pillars',
    'employees',
    'profiles_psych',
    'papi_scores',
    'strengths',
    'performance_yearly',
    'competencies_yearly',
]

def download_sheets():
    url = f'https://docs.google.com/spreadsheets/d/{SHEET_ID}/export?format=xlsx'
    print('Downloading dataset from Google Sheets...')
    r = requests.get(url, timeout=120)
    r.raise_for_status()
    print(f'Downloaded {len(r.content)/1024:.1f} KB')
    return pd.ExcelFile(io.BytesIO(r.content))

def clean_df(df: pd.DataFrame) -> pd.DataFrame:
    """Remove all-NaN rows; convert all values to Python-native types safe for JSON."""
    df = df.dropna(how='all').copy()
    # Replace all NaN/NaT with None across every column
    df = df.where(pd.notnull(df), None)
    return df

def upsert_batch(table: str, records: list):
    """Upsert a batch of records, retry once on failure."""
    try:
        sb.table(table).upsert(records, on_conflict='*').execute()
    except Exception:
        # Fallback: insert ignoring conflicts
        try:
            sb.table(table).insert(records, returning='minimal').execute()
        except Exception as e2:
            print(f'    Batch error: {str(e2)[:80]}')

def import_table(table: str, df: pd.DataFrame):
    df = clean_df(df)
    records = df.to_dict(orient='records')
    total   = len(records)
    batches = (total + BATCH_SIZE - 1) // BATCH_SIZE

    print(f'\n  {table:<30} {total:>6} rows → {batches} batches')

    for i in range(batches):
        batch = records[i * BATCH_SIZE:(i + 1) * BATCH_SIZE]
        # Convert batch: ensure all values are Python-native JSON-serializable types
        clean_batch = []
        for rec in batch:
            clean_rec = {}
            for k, v in rec.items():
                if v is None:
                    clean_rec[k] = None
                elif hasattr(v, 'item'):        # numpy scalar → Python native
                    clean_rec[k] = v.item()
                elif isinstance(v, float) and (v != v):  # NaN check
                    clean_rec[k] = None
                else:
                    clean_rec[k] = v
            clean_batch.append(clean_rec)

        sb.table(table).upsert(clean_batch).execute()
        done = min((i + 1) * BATCH_SIZE, total)
        pct  = done / total * 100
        bar  = '#' * int(pct / 5) + '.' * (20 - int(pct / 5))
        print(f'\r    [{bar}] {done}/{total} ({pct:.0f}%)', end='', flush=True)
        time.sleep(0.05)  # avoid rate limiting

    print(f'\r    [{"#"*20}] {total}/{total} (100%) ✓')

def main():
    xl = download_sheets()
    sheets = {s: xl.parse(s) for s in xl.sheet_names}

    # Save TV/TGV reference sheet separately
    if 'Talent Variable (TV) & Talent G' in sheets:
        tv_df = sheets['Talent Variable (TV) & Talent G']
        tv_df.to_csv(
            os.path.join(os.path.dirname(__file__), '..', 'data', 'tv_tgv_reference.csv'),
            index=False
        )
        print('Saved TV/TGV reference → data/tv_tgv_reference.csv')

    print('\nStarting import...')
    print('='*60)

    success, failed = [], []
    for table in IMPORT_ORDER:
        if table not in sheets:
            print(f'\n  {table:<30} SKIP (sheet not found)')
            continue
        try:
            import_table(table, sheets[table])
            success.append(table)
        except Exception as e:
            print(f'\n  {table:<30} ERROR: {e}')
            failed.append(table)

    print('\n' + '='*60)
    print(f'Import complete: {len(success)} OK, {len(failed)} failed')
    if failed:
        print(f'Failed: {failed}')

    # Verify row counts
    print('\nVerifying row counts:')
    print('-'*50)
    for table in IMPORT_ORDER:
        try:
            r = sb.table(table).select('*', count='exact').limit(1).execute()
            print(f'  {table:<30} {r.count:>6} rows')
        except Exception as e:
            print(f'  {table:<30} ERROR: {e}')

if __name__ == '__main__':
    main()
