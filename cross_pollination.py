#!/usr/bin/env python3
"""AF64 Cross-Pollination — Context sharing between departments.

When a conversation thread involves agents from multiple departments,
this module injects brief context about what the other departments do,
enabling cross-functional collaboration.

Customize DEPARTMENT_BRIEFS for your organization's structure.
"""


# Department context briefs — customize these for your org
DEPARTMENT_BRIEFS = {
    "engineering": "Builds and maintains technical infrastructure, APIs, and tools.",
    "content": "Creates, curates, and publishes content across all channels.",
    "creative": "Visual design, branding, and creative direction.",
    "legal": "Policy, ethics, compliance, and canonical authority.",
    "music": "Audio production, composition, and sonic branding.",
    "strategy": "Market analysis, financial positioning, and organizational efficiency.",
    "operations": "Administrative coordination, scheduling, and CEO support.",
}


def detect_cross_department_thread(conn, msg, agent_registry):
    """Detect which departments are involved in a conversation thread.
    
    Args:
        conn: Not used in API mode (kept for interface compatibility)
        msg: Message dict with thread context
        agent_registry: Dict of agent_id -> agent_info (must include 'department')
    
    Returns:
        Set of department names involved in the thread
    """
    departments = set()
    
    # Check the sender's department
    sender = msg.get("from_agent", "").lower()
    if sender in agent_registry:
        dept = agent_registry[sender].get("department", "")
        if dept:
            departments.add(dept.lower())
    
    # Check to_agent departments
    for target in (msg.get("to_agent") or []):
        target_lower = target.lower()
        if target_lower in agent_registry:
            dept = agent_registry[target_lower].get("department", "")
            if dept:
                departments.add(dept.lower())
    
    return departments


def get_cross_pollination_context(agent_name, thread_departments, agent_registry):
    """Generate cross-department context for an agent.
    
    Args:
        agent_name: The agent who will receive this context
        thread_departments: Set of departments involved in the thread
        agent_registry: Dict of agent_id -> agent_info
    
    Returns:
        String of context to inject into the agent's system prompt, or None
    """
    agent_info = agent_registry.get(agent_name, {})
    agent_dept = (agent_info.get("department") or "").lower()
    
    # Only inject context about OTHER departments
    other_depts = thread_departments - {agent_dept}
    
    if not other_depts:
        return None
    
    lines = ["\n=== CROSS-DEPARTMENT CONTEXT ==="]
    lines.append("Other departments in this conversation:")
    
    for dept in sorted(other_depts):
        brief = DEPARTMENT_BRIEFS.get(dept, f"The {dept} department.")
        lines.append(f"• **{dept.title()}**: {brief}")
    
    lines.append("Collaborate naturally. Reference your own expertise while respecting theirs.")
    lines.append("=== END CROSS-DEPARTMENT CONTEXT ===")
    
    return "\n".join(lines)
