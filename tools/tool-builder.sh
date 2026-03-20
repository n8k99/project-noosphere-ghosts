#!/bin/bash
# Tool Builder — spawns Claude Code to build tools from ghost specs
# Clean environment to prevent SBCL env vars from confusing Claude Code auth
export HOME=/root
export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin"
export TERM=dumb
# Unset anything that might interfere with Claude Code's OAuth
unset ANTHROPIC_API_KEY CLAUDE_API_KEY XDG_CONFIG_HOME XDG_DATA_HOME
unset SBCL_HOME ASDF_OUTPUT_TRANSLATIONS

SPEC_FILE="$1"
TOOL_NAME="$2"
AGENT_ID="${3:-ghost}"
WORKSPACE="/root/gotcha-workspace"
LOG="/tmp/tool-builder-${TOOL_NAME}.log"

if [ -z "$SPEC_FILE" ] || [ -z "$TOOL_NAME" ]; then
    echo "Usage: tool-builder.sh <spec_file> <tool_name> [agent_id]"
    exit 1
fi

SPEC=$(cat "$SPEC_FILE")
TOOL_DIR="$WORKSPACE/tools/$TOOL_NAME"
mkdir -p "$TOOL_DIR"

echo "[$(date -u +%H:%M:%S)] Starting build: $TOOL_NAME (from $AGENT_ID)" > "$LOG"

# Use claude directly as root (without --dangerously-skip-permissions)
# The -p flag just prints output; we need actual file writes
# So use the full interactive mode with a here-doc via expect/script

cd "$WORKSPACE"

# Write the prompt to a file  
cat > "/tmp/builder-prompt-${TOOL_NAME}.txt" << PROMPT_EOF
Build a Python tool in ${TOOL_DIR}/ based on this specification.

WORKSPACE: ${WORKSPACE}
PYTHON VENV: ${WORKSPACE}/.venv/bin/python3
DB CONFIG: sys.path.insert(0, '${WORKSPACE}'); from tools._config import PG_CONFIG, PG_CONNECTION_STRING
DB: PostgreSQL at 127.0.0.1:5432, user=chronicle, password=chronicle2026, db=master_chronicle

REQUIREMENTS:
1. Use psycopg2 for database access (installed in .venv)
2. Write a standalone Python script with argparse + importable functions
3. Write a README.md explaining the tool
4. Test it works: ${WORKSPACE}/.venv/bin/python3 <script> --help
5. Only create files in ${TOOL_DIR}/

SPECIFICATION:
${SPEC}
PROMPT_EOF

# Run claude code with the prompt file
HOME=/root PATH="/root/.local/bin:/root/.nvm/versions/node/v22.22.0/bin:/usr/local/bin:/usr/bin:/bin" TERM=dumb \
  claude -p "$(cat /tmp/builder-prompt-${TOOL_NAME}.txt)" \
  --allowedTools "Write,Edit,Bash" \
  --model sonnet \
  >> "$LOG" 2>&1

EXIT_CODE=$?
echo "[$(date -u +%H:%M:%S)] Claude exit code: $EXIT_CODE" >> "$LOG"

# Check if files were created
PY_COUNT=$(find "$TOOL_DIR" -name "*.py" | wc -l)
echo "[$(date -u +%H:%M:%S)] Python files: $PY_COUNT" >> "$LOG"

if [ "$PY_COUNT" -gt 0 ]; then
    echo "BUILD_SUCCESS" >> "$LOG"
    
    # Update manifest
    {
      echo ""
      echo "## $TOOL_NAME"
      echo "- Built by ghost: $AGENT_ID"
      echo "- Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "- Files: $(find $TOOL_DIR -name '*.py' -exec basename {} \; | tr '\n' ', ')"
    } >> "$WORKSPACE/tools/manifest.md"
    
    # Post success
    curl -s -X POST http://127.0.0.1:8080/api/conversations \
      -H "Content-Type: application/json" \
      -H "X-API-Key: dpn-nova-2026" \
      -d "$(python3 -c "
import json
files = '$(find $TOOL_DIR -name '*.py' -exec basename {} \;)'
msg = '✅ BUILD SUCCESS: $TOOL_NAME\n\nFiles created:\n' + '\n'.join('- ' + f for f in files.strip().split('\n') if f) + '\n\nTool is ready for use in gotcha-workspace/tools/$TOOL_NAME/'
print(json.dumps({
    'from_agent': '$AGENT_ID',
    'to_agent': ['$AGENT_ID', 'noosphere'],
    'message': msg,
    'channel': 'noosphere',
    'metadata': {'source': 'tool_builder', 'tool_name': '$TOOL_NAME', 'status': 'success'}
}))
")" > /dev/null 2>&1
else
    echo "BUILD_FAILED" >> "$LOG"
    
    curl -s -X POST http://127.0.0.1:8080/api/conversations \
      -H "Content-Type: application/json" \
      -H "X-API-Key: dpn-nova-2026" \
      -d "$(python3 -c "
import json
print(json.dumps({
    'from_agent': '$AGENT_ID',
    'to_agent': ['$AGENT_ID', 'noosphere'],
    'message': '❌ BUILD FAILED: $TOOL_NAME\nClaude Code could not write files. Log at /tmp/tool-builder-$TOOL_NAME.log',
    'channel': 'noosphere',
    'metadata': {'source': 'tool_builder', 'tool_name': '$TOOL_NAME', 'status': 'failed'}
}))
")" > /dev/null 2>&1
fi

exit $EXIT_CODE
