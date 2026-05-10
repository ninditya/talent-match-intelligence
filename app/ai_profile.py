import os
import json
import requests
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"

def _get_secret(key: str, default: str = "") -> str:
    try:
        import streamlit as st
        return st.secrets.get(key, os.getenv(key, default))
    except Exception:
        return os.getenv(key, default)


def generate_job_profile(
    role_name: str,
    job_level: str,
    role_purpose: str,
    top_tgvs: dict,
    top_strengths: list[str],
) -> dict:
    """
    Call an LLM via OpenRouter to generate a structured job profile.
    Returns: {job_requirements, job_description, key_competencies}
    """
    prompt = f"""
You are an expert HR analyst. Generate a structured job profile based on the following talent intelligence data.

Role: {role_name}
Level: {job_level}
Purpose: {role_purpose}

Top Talent Group Variables (TGV) scores from benchmark employees:
{json.dumps(top_tgvs, indent=2)}

Common CliftonStrengths themes among top performers:
{', '.join(top_strengths)}

Return a JSON object with exactly these keys:
{{
  "job_requirements": ["bullet 1", "bullet 2", ...],   // 6-8 specific requirements
  "job_description": "2-3 sentence narrative description",
  "key_competencies": ["competency 1", "competency 2", ...]  // 5-7 key competencies
}}

Be specific, data-driven, and business-ready. No markdown, just raw JSON.
"""

    headers = {
        "Authorization": f"Bearer {_get_secret('OPENROUTER_API_KEY')}",
        "Content-Type":  "application/json",
        "HTTP-Referer":  "https://talent-match-intelligence.streamlit.app",
        "X-Title":       "Talent Match Intelligence",
    }

    payload = {
        "model": _get_secret("OPENROUTER_MODEL", "minimax/minimax-m2.5:free"),
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.4,
    }

    try:
        resp = requests.post(OPENROUTER_URL, headers=headers, json=payload, timeout=30)
        resp.raise_for_status()
        content = resp.json()["choices"][0]["message"]["content"].strip()

        # Strip markdown code fences if present
        if content.startswith("```"):
            content = content.split("```")[1]
            if content.startswith("json"):
                content = content[4:]

        return json.loads(content)

    except Exception as e:
        return {
            "job_requirements": [f"[AI generation failed: {e}]"],
            "job_description":  f"Role: {role_name} | Level: {job_level}. {role_purpose}",
            "key_competencies": list(top_tgvs.keys()),
        }
