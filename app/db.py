import os
from supabase import create_client, Client
from dotenv import load_dotenv
import pandas as pd

load_dotenv()

_client: Client | None = None


def get_client() -> Client:
    global _client
    if _client is None:
        url = os.environ["SUPABASE_URL"]
        key = os.environ["SUPABASE_KEY"]
        _client = create_client(url, key)
    return _client


def query(sql: str, params: dict | None = None) -> pd.DataFrame:
    """Execute raw SQL via Supabase Postgres REST (rpc) and return a DataFrame."""
    client = get_client()
    result = client.rpc("execute_sql", {"query": sql, "params": params or {}}).execute()
    return pd.DataFrame(result.data)


def fetch_table(table: str, columns: str = "*", limit: int = 10000) -> pd.DataFrame:
    """Fetch a full table or specific columns as a DataFrame."""
    client = get_client()
    result = client.table(table).select(columns).limit(limit).execute()
    return pd.DataFrame(result.data)
