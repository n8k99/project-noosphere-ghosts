#!/usr/bin/env python3
"""
Nightly Memory Synthesis — runs at 11:55 PM ET
1. Reads all agent_daily_memory entries for today
2. Uses Ollama (llama3.2) to generate daily_summary for each agent
3. On Sundays: rolls up the week into weekly_executive_summary
"""

import json
import sys
import requests
import psycopg2
import psycopg2.extras
from datetime import datetime, date, timedelta

DB_CONFIG = {
    'host': '127.0.0.1',
    'port': 5432,
    'dbname': 'master_chronicle',
    'user': 'chronicle',
    'password': 'chronicle2026'
}

OLLAMA_URL = 'http://127.0.0.1:11434/api/generate'
MODEL = 'llama3.2'

def ollama_generate(prompt, max_tokens=500):
    """Generate text via local Ollama."""
    try:
        resp = requests.post(OLLAMA_URL, json={
            'model': MODEL,
            'prompt': prompt,
            'stream': False,
            'options': {'num_predict': max_tokens, 'temperature': 0.3}
        }, timeout=60)
        return resp.json().get('response', '').strip()
    except Exception as e:
        print(f"  [ollama-error] {e}")
        return None

def synthesize_daily_summaries(conn, today):
    """Generate daily_summary for each agent that has memory entries today."""
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    cur.execute("""
        SELECT m.id, m.agent_id, a.full_name, a.role, a.department,
               m.actions_taken, m.decisions_made, m.knowledge_gained,
               m.blockers, m.handoffs, m.plan_tomorrow
        FROM agent_daily_memory m
        JOIN agents a ON a.id = m.agent_id
        WHERE m.log_date = %s AND m.daily_summary IS NULL
    """, (today,))
    
    rows = cur.fetchall()
    print(f"  Synthesizing {len(rows)} agent daily summaries...")
    
    for row in rows:
        sections = []
        if row['actions_taken']:
            sections.append(f"Actions: {row['actions_taken'][:300]}")
        if row['decisions_made']:
            sections.append(f"Decisions: {row['decisions_made'][:200]}")
        if row['handoffs']:
            sections.append(f"Handoffs: {row['handoffs'][:200]}")
        if row['blockers']:
            sections.append(f"Blockers: {row['blockers'][:200]}")
        
        if not sections:
            continue
            
        prompt = f"""Summarize this agent's daily activity in 2-3 sentences.
Agent: {row['full_name']} ({row['role']}, {row['department']})
{chr(10).join(sections)}

Summary:"""
        
        summary = ollama_generate(prompt, 150)
        if summary:
            cur.execute(
                "UPDATE agent_daily_memory SET daily_summary = %s, updated_at = NOW() WHERE id = %s",
                (summary, row['id'])
            )
            print(f"    ✓ {row['agent_id']}: {summary[:80]}...")
    
    conn.commit()
    return len(rows)

def generate_weekly_summary(conn, week_start, week_end):
    """Roll up daily memories into weekly executive summary."""
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    
    # Get all summaries for the week grouped by department
    cur.execute("""
        SELECT a.department, array_agg(DISTINCT a.full_name) as agents,
               string_agg(DISTINCT m.daily_summary, '; ' ORDER BY m.daily_summary) as summaries,
               COUNT(DISTINCT m.agent_id) as active_agents,
               COUNT(*) as total_entries
        FROM agent_daily_memory m
        JOIN agents a ON a.id = m.agent_id
        WHERE m.log_date BETWEEN %s AND %s AND m.daily_summary IS NOT NULL
        GROUP BY a.department
        ORDER BY a.department
    """, (week_start, week_end))
    
    dept_data = cur.fetchall()
    if not dept_data:
        print("  No data for weekly summary")
        return
    
    # Generate per-department summaries
    dept_summaries = {}
    dept_column_map = {
        'Engineering': 'engineering_summary',
        'art': 'art_summary',
        'content_brand': 'content_brand_summary',
        'legal': 'legal_summary',
        'strategic_office': 'strategy_summary',
        'music': 'music_summary',
        'support': 'support_summary',
        'cross_functional': 'cross_functional_summary',
    }
    
    all_summaries = []
    for dept in dept_data:
        dept_name = dept['department'] or 'unknown'
        prompt = f"""Summarize this department's weekly activity in 3-4 sentences for an executive briefing.
Department: {dept_name}
Active agents: {dept['active_agents']}
Activity: {(dept['summaries'] or '')[:600]}

Department summary:"""
        
        summary = ollama_generate(prompt, 200)
        col = dept_column_map.get(dept_name, 'cross_functional_summary')
        dept_summaries[col] = summary
        all_summaries.append(f"**{dept_name}** ({dept['active_agents']} agents): {summary}")
        print(f"    {dept_name}: {(summary or '')[:80]}...")
    
    # Generate executive brief
    brief_prompt = f"""Write a one-page executive summary for Nathan Eckenrode (CEO) covering this week's organizational activity at Eckenrode Muziekopname.
Week: {week_start} to {week_end}

Department summaries:
{chr(10).join(all_summaries)}

Write a concise executive brief with: Key Achievements, Active Projects, Blockers/Risks, and Recommended Actions."""
    
    executive_brief = ollama_generate(brief_prompt, 500)
    
    # Get tools built this week
    cur.execute("""
        SELECT message FROM conversations 
        WHERE from_agent = 'builder' AND message LIKE '%%BUILD SUCCESS%%'
        AND created_at BETWEEN %s AND %s
    """, (week_start, week_end + timedelta(days=1)))
    tools_built = '\n'.join(r[0][:100] for r in cur.fetchall()) or None
    
    # Upsert weekly summary
    cols = list(dept_summaries.keys())
    vals = [dept_summaries[c] for c in cols]
    
    cur.execute(f"""
        INSERT INTO weekly_executive_summary (week_start, week_end, {', '.join(cols)}, tools_built, executive_brief)
        VALUES (%s, %s, {', '.join(['%s'] * len(cols))}, %s, %s)
        ON CONFLICT (week_start) DO UPDATE SET
        {', '.join(f'{c} = EXCLUDED.{c}' for c in cols)},
        tools_built = EXCLUDED.tools_built,
        executive_brief = EXCLUDED.executive_brief
    """, [week_start, week_end] + vals + [tools_built, executive_brief])
    
    conn.commit()
    print(f"  ✓ Weekly summary saved for {week_start} — {week_end}")

def main():
    today = date.today()
    print(f"[{datetime.now().strftime('%H:%M:%S')}] Nightly memory synthesis for {today}")
    
    conn = psycopg2.connect(**DB_CONFIG)
    
    # 1. Synthesize daily summaries
    count = synthesize_daily_summaries(conn, today)
    print(f"  Processed {count} daily entries")
    
    # 2. On Sundays, generate weekly summary
    if today.weekday() == 6:  # Sunday
        week_start = today - timedelta(days=6)  # Monday
        print(f"  Sunday — generating weekly summary {week_start} to {today}")
        generate_weekly_summary(conn, week_start, today)
    
    conn.close()
    print(f"[{datetime.now().strftime('%H:%M:%S')}] Done")

if __name__ == '__main__':
    main()
