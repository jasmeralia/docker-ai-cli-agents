#!/usr/bin/env bash
# Claude Code status line script
# Prints: ctx 42% | sess 31% | week 18%

# Exit silently if jq is not available
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)

ctx=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
sess=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

if [ -n "$ctx" ]; then
    ctx_str="ctx $(printf '%.0f' "$ctx")%"
else
    ctx_str="ctx --"
fi

if [ -n "$sess" ]; then
    sess_str="sess $(printf '%.0f' "$sess")%"
else
    sess_str="sess --"
fi

if [ -n "$week" ]; then
    week_str="week $(printf '%.0f' "$week")%"
else
    week_str="week --"
fi

echo "${ctx_str} | ${sess_str} | ${week_str}"
