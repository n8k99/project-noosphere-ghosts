#!/usr/bin/env python3
"""Write ghost memory to vault_notes daily note column.
Usage: write_vault_memory.py <agent_id> <action> <summary>
Appends to {agent_id}_memories column on today's daily note."""

import sys
import psycopg2
from datetime import datetime

def main():
    if len(sys.argv) < 4:
        print("Usage: write_vault_memory.py <agent_id> <action> <summary>", file=sys.stderr)
        sys.exit(1)

    agent_id = sys.argv[1].replace("-", "_")
    action = sys.argv[2]
    summary = " ".join(sys.argv[3:])[:200]

    today = datetime.now().strftime("%Y-%m-%d")
    now = datetime.now().strftime("%H:%M")
    daily_path = f"Areas/N8K99Notes/Daily Notes/{today}.md"
    mem_column = f"{agent_id}_memories"
    entry = f"{now} [{action}] {summary}"

    try:
        conn = psycopg2.connect(dbname="master_chronicle", user="chronicle", password="chronicle2026", host="127.0.0.1", port=5432)
        cur = conn.cursor()
        # Verify column exists (prevent injection via agent_id)
        cur.execute("""
            SELECT column_name FROM information_schema.columns
            WHERE table_name = 'vault_notes' AND column_name = %s
        """, (mem_column,))
        if not cur.fetchone():
            print(f"NO_COLUMN:{mem_column}", file=sys.stderr)
            sys.exit(1)
        # Append to column
        cur.execute(f"""
            UPDATE vault_notes
            SET {mem_column} = COALESCE({mem_column}, '') || E'\\n' || %s
            WHERE path = %s
        """, (entry, daily_path))
        conn.commit()
        if cur.rowcount == 1:
            print(f"OK:{agent_id}:{today}")
        else:
            print(f"NO_ROW:{daily_path}", file=sys.stderr)
        cur.close()
        conn.close()
    except Exception as e:
        print(f"ERROR:{e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
