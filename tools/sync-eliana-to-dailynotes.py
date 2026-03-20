#!/usr/bin/env python3
"""
Sync Eliana memories from Areas/Agents/Eliana/memory/ to vault_notes.eliana_memories
Matches by date: 2026-02-21.md -> Areas/N8K99Notes/Daily Notes/2026-02-21.md
"""

import psycopg2
from datetime import datetime

DB_CONFIG = {
    "host": "127.0.0.1",
    "port": 5432,
    "dbname": "master_chronicle",
    "user": "chronicle",
    "password": "chronicle2026"
}

def main():
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()
    
    # Get all Eliana daily memory files
    cur.execute("""
        SELECT path, content, note_date 
        FROM vault_notes 
        WHERE path LIKE 'Areas/Agents/Eliana/memory/____-__-__.md'
        AND note_date IS NOT NULL
    """)
    
    memories = cur.fetchall()
    print(f"Found {len(memories)} Eliana daily memories")
    
    updated = 0
    for mem_path, content, note_date in memories:
        # Find matching daily note
        daily_path = f"Areas/N8K99Notes/Daily Notes/{note_date}.md"
        
        cur.execute("""
            UPDATE vault_notes 
            SET eliana_memories = %s
            WHERE path = %s
            RETURNING id
        """, (content, daily_path))
        
        if cur.fetchone():
            updated += 1
            print(f"  ✓ {note_date}")
        else:
            print(f"  - {note_date} (no daily note)")
    
    conn.commit()
    print(f"\nUpdated {updated} daily notes with Eliana memories")
    
    cur.close()
    conn.close()

if __name__ == "__main__":
    main()
