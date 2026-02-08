#!/usr/bin/env python3
"""
Agent Guard - PreToolUse hook for enforcing orchestrator mode and routing rules.

Rules enforced:
1. Main thread cannot Edit/Write/NotebookEdit code files (delegate via /act)
2. Agents cannot edit files outside their allowed patterns
3. Block dangerous git commands (push --force)
4. Block dangerous gh CLI commands (pr merge, repo delete)
"""

import json
import re
import sys
from fnmatch import fnmatch
from pathlib import Path

# Code file extensions that main thread cannot edit
CODE_EXTENSIONS = {
    '.cs', '.tsx', '.ts', '.js', '.jsx', '.json', '.yml', '.yaml',
    '.sql', '.scss', '.css', '.html', '.xml', '.sh', '.ps1', '.py',
    '.csproj', '.sln', '.props', '.targets'
}

# Files main thread CAN edit
MAIN_ALLOWED_PATTERNS = [
    'CLAUDE.md',
    'docs/plan/*.md',
    '~/.claude/plans/*.md',
    '.claude/*.md',
    '.claude/**/*.md',
    '.claude/**/*.json',
]

# Agent -> allowed file patterns
AGENT_ROUTING = {
    'claude-code-hacker': [
        '.claude/**',
        '.mcp.json',
        'scripts/*-guard.sh',
        'CLAUDE.md',
    ],
    'main': MAIN_ALLOWED_PATTERNS,
    'frontend-developer': [
        'services/admin-dashboard/**',
        'services/web-portal/**',
    ],
    'frontend-qa': [
        'services/admin-dashboard/**/*.test.tsx',
        'services/admin-dashboard/**/*.test.ts',
        'services/admin-dashboard/**/*.spec.tsx',
        'services/admin-dashboard/**/*.spec.ts',
        'services/web-portal/**/*.test.*',
        'services/web-portal/**/*.spec.*',
    ],
    'backend-developer': [
        'services/**/*.cs',
        'src/shared/**/*.cs',
        'services/db/migrations_v2/**',
    ],
    'backend-qa': [
        'tests/**/*.cs',
        'testing/**/*.ps1',
        'testing/**/*.sh',
    ],
    'platform-windows-developer': [
        'agent/windows/**',
    ],
    'platform-linux-developer': [
        'agent/linux/**',
    ],
    'platform-macos-developer': [
        'agent/macos/**',
    ],
    'platform-lead-developer': [
        'agent/shared/**',
    ],
    'platform-qa': [
        'agent/windows/tests/**',
        'agent/linux/tests/**',
        'agent/macos/tests/**',
    ],
    'platform-build-engineer': [
        'agent/**/*.wixproj',
        'agent/**/*.wxs',
        'agent/**/packaging/**',
    ],
    'devops-engineer': [
        'docker-compose*.yml',
        'Dockerfile*',
        '.github/workflows/**',
    ],
    'code-refactorer': [
        'services/**',
        'src/**',
        'agent/**',
        'tests/**',
    ],
    'git-commit-helper': [],  # No file edits, only git commands
    'ui-design-lead': [
        'docs/plan/*/design/**',
    ],
    'ui-design-ux': [
        'docs/plan/*/design/**',
    ],
}


def find_agent_from_transcript(transcript_path: str, tool_use_id: str) -> str:
    """Find which agent made this tool call."""
    if not tool_use_id:
        return "main"

    try:
        agentid_to_type = {}
        task_call_types = {}

        if transcript_path and Path(transcript_path).exists():
            with open(transcript_path) as f:
                for line in f:
                    try:
                        entry = json.loads(line.strip())
                        msg = entry.get("message", {})
                        content = msg.get("content", [])
                        if not isinstance(content, list):
                            continue

                        for item in content:
                            if not isinstance(item, dict):
                                continue

                            if item.get("name") == "Task":
                                inp = item.get("input", {})
                                subagent = inp.get("subagent_type")
                                task_id = item.get("id")
                                if subagent and task_id:
                                    task_call_types[task_id] = subagent

                            if item.get("type") == "tool_result":
                                result_id = item.get("tool_use_id", "")
                                result_content = item.get("content", "")
                                if result_id in task_call_types:
                                    text_to_search = ""
                                    if isinstance(result_content, str):
                                        text_to_search = result_content
                                    elif isinstance(result_content, list):
                                        for c in result_content:
                                            if isinstance(c, dict) and c.get("type") == "text":
                                                text_to_search += c.get("text", "")
                                    if text_to_search:
                                        match = re.search(r'agentId[:\s]+([a-f0-9]+)', text_to_search)
                                        if match:
                                            agentid_to_type[match.group(1)] = task_call_types[result_id]
                    except Exception:
                        continue

        transcript_file = Path(transcript_path)
        subagents_dir = transcript_file.parent / transcript_file.stem / "subagents"

        if subagents_dir.exists():
            for agent_file in subagents_dir.glob("agent-*.jsonl"):
                agent_id = agent_file.stem.replace("agent-", "")
                try:
                    with open(agent_file) as f:
                        for line in f:
                            try:
                                entry = json.loads(line.strip())
                                msg = entry.get("message", {})
                                content = msg.get("content", [])
                                if not isinstance(content, list):
                                    continue
                                for item in content:
                                    if isinstance(item, dict) and item.get("id") == tool_use_id:
                                        return agentid_to_type.get(agent_id, f"agent:{agent_id}")
                            except Exception:
                                continue
                except Exception:
                    continue

        return "main"
    except Exception:
        return "main"


def is_code_file(file_path: str) -> bool:
    """Check if file is a code file based on extension."""
    return Path(file_path).suffix.lower() in CODE_EXTENSIONS


def matches_pattern(file_path: str, pattern: str) -> bool:
    """Check if file path matches a glob pattern."""
    # Normalize paths
    file_path = file_path.replace('\\', '/')
    pattern = pattern.replace('\\', '/')

    # Handle ~ expansion
    if pattern.startswith('~'):
        pattern = str(Path.home()) + pattern[1:]

    # Use fnmatch for glob matching
    if '**' in pattern:
        # For ** patterns, check if path starts with prefix and matches suffix
        parts = pattern.split('**')
        if len(parts) == 2:
            prefix, suffix = parts
            prefix = prefix.rstrip('/')
            suffix = suffix.lstrip('/')
            if prefix and not file_path.startswith(prefix):
                return False
            if suffix:
                # Match suffix pattern against remaining path
                remaining = file_path[len(prefix):].lstrip('/') if prefix else file_path
                return fnmatch(remaining, '*' + suffix) or fnmatch(remaining, '**/' + suffix)
            return file_path.startswith(prefix) if prefix else True

    return fnmatch(file_path, pattern)


def agent_can_edit(agent: str, file_path: str) -> bool:
    """Check if agent is allowed to edit this file."""
    patterns = AGENT_ROUTING.get(agent, [])
    for pattern in patterns:
        if matches_pattern(file_path, pattern):
            return True
    return False


def check_dangerous_git(command: str) -> tuple[bool, str]:
    """Check for dangerous git commands."""
    if re.search(r'git\s+push\s+.*(-f|--force)', command):
        return True, "BLOCKED: git push --force is not allowed. Use regular git push."
    return False, ""


def check_dangerous_gh(command: str) -> tuple[bool, str]:
    """Check for dangerous gh CLI commands."""
    if re.search(r'gh\s+pr\s+merge', command):
        return True, "BLOCKED: gh pr merge is not allowed. PRs must be merged via GitHub UI."
    if re.search(r'gh\s+repo\s+delete', command):
        return True, "BLOCKED: gh repo delete is not allowed."
    return False, ""


def main():
    # Read hook input from stdin
    hook_input = json.load(sys.stdin)

    tool_name = hook_input.get("tool_name", "")
    tool_input = hook_input.get("tool_input", {})
    tool_use_id = hook_input.get("tool_use_id", "")
    transcript_path = hook_input.get("transcript_path", "")

    # Identify which agent is making this call
    agent = find_agent_from_transcript(transcript_path, tool_use_id)

    # Rule 1: Main thread cannot edit code files
    if tool_name in ("Edit", "Write", "NotebookEdit"):
        file_path = tool_input.get("file_path", "")

        if agent == "main":
            # Check if it's a code file
            if is_code_file(file_path):
                # Check if it matches allowed patterns for main
                allowed = False
                for pattern in MAIN_ALLOWED_PATTERNS:
                    if matches_pattern(file_path, pattern):
                        allowed = True
                        break

                if not allowed:
                    print(json.dumps({
                        "decision": "block",
                        "reason": f"ORCHESTRATOR MODE: Cannot edit code file '{file_path}'. Delegate to appropriate agent via /act or Task tool."
                    }))
                    return

        # Rule 2: Agents can only edit files in their allowed patterns
        elif agent != "main" and not agent.startswith("agent:"):
            if not agent_can_edit(agent, file_path):
                print(json.dumps({
                    "decision": "block",
                    "reason": f"ROUTING VIOLATION: Agent '{agent}' cannot edit '{file_path}'. Check .claude/rules/routing-rules.md for allowed patterns."
                }))
                return

    # Rule 3 & 4: Check dangerous commands
    if tool_name == "Bash":
        command = tool_input.get("command", "")

        # Rule 3: Dangerous git commands
        blocked, reason = check_dangerous_git(command)
        if blocked:
            print(json.dumps({
                "decision": "block",
                "reason": reason
            }))
            return

        # Rule 4: Dangerous gh CLI commands
        blocked, reason = check_dangerous_gh(command)
        if blocked:
            print(json.dumps({
                "decision": "block",
                "reason": reason
            }))
            return

    # Allow the tool call
    print(json.dumps({"decision": "allow"}))


if __name__ == "__main__":
    main()
