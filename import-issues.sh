#!/bin/bash
set -euo pipefail

# Resolve gh across Git Bash, WSL, and native bash
if ! command -v gh &>/dev/null; then
  if [ -f "/c/Program Files/GitHub CLI/gh.exe" ]; then
    gh() { "/c/Program Files/GitHub CLI/gh.exe" "$@"; }
  elif [ -f "/mnt/c/Program Files/GitHub CLI/gh.exe" ]; then
    gh() { "/mnt/c/Program Files/GitHub CLI/gh.exe" "$@"; }
  else
    echo "❌ gh CLI not found. Install from https://cli.github.com/" >&2
    exit 1
  fi
fi

# Resolve jq across Git Bash, WSL, and native bash
if ! command -v jq &>/dev/null; then
  if [ -f "/c/ProgramData/chocolatey/bin/jq.exe" ]; then
    jq() { "/c/ProgramData/chocolatey/bin/jq.exe" "$@"; }
  elif [ -f "/mnt/c/ProgramData/chocolatey/bin/jq.exe" ]; then
    jq() { "/mnt/c/ProgramData/chocolatey/bin/jq.exe" "$@"; }
  else
    echo "❌ jq not found. Install via: choco install jq" >&2
    exit 1
  fi
fi

# ─── CONFIG ────────────────────────────────────────────────────────────────────
REPO="AIS-Commercial-Business-Unit/Helix"
ORG="AIS-Commercial-Business-Unit"
PROJECT_NUMBER=1

# ─── GET PROJECT ID ────────────────────────────────────────────────────────────
echo "🔍 Fetching project ID..."
PROJECT_ID=$(gh api graphql -f query='
  query($org: String!, $num: Int!) {
    organization(login: $org) {
      projectV2(number: $num) { id }
    }
  }' -f org="$ORG" -F num=$PROJECT_NUMBER \
  --jq '.data.organization.projectV2.id')
echo "   PROJECT_ID=$PROJECT_ID"

# ─── DISCOVER FIELD & OPTION IDS ───────────────────────────────────────────────
echo "🔍 Fetching field IDs and option IDs..."
FIELDS_JSON=$(gh api graphql -f query='
  query($projectId: ID!) {
    node(id: $projectId) {
      ... on ProjectV2 {
        fields(first: 30) {
          nodes {
            ... on ProjectV2Field              { id name }
            ... on ProjectV2IterationField     { id name }
            ... on ProjectV2SingleSelectField  { id name options { id name } }
          }
        }
      }
    }
  }' -f projectId="$PROJECT_ID" \
  --jq '.data.node.fields.nodes')

STATUS_FIELD_ID=$(echo "$FIELDS_JSON"    | jq -r '.[] | select(.name=="Status")        | .id')
DUE_FIELD_ID=$(echo "$FIELDS_JSON"       | jq -r '.[] | select(.name=="TargetDueDate") | .id')
EPIC_FIELD_ID=$(echo "$FIELDS_JSON"      | jq -r '.[] | select(.name=="Epic")          | .id')

STATUS_IN_PROGRESS=$(echo "$FIELDS_JSON" | jq -r '.[] | select(.name=="Status") | .options[] | select(.name=="In Progress") | .id')
STATUS_BACKLOG=$(echo "$FIELDS_JSON"     | jq -r '.[] | select(.name=="Status") | .options[] | select(.name=="Backlog")     | .id')
EPIC_FRAMEWORK=$(echo "$FIELDS_JSON"     | jq -r '.[] | select(.name=="Epic")   | .options[] | select(.name=="Helix - Framework Tasks") | .id')

echo "   STATUS_FIELD_ID=$STATUS_FIELD_ID"
echo "   DUE_FIELD_ID=$DUE_FIELD_ID"
echo "   EPIC_FIELD_ID=$EPIC_FIELD_ID"
echo "   STATUS_IN_PROGRESS=$STATUS_IN_PROGRESS"
echo "   STATUS_BACKLOG=$STATUS_BACKLOG"
echo "   EPIC_FRAMEWORK=$EPIC_FRAMEWORK"

# ─── VALIDATE IDs ─────────────────────────────────────────────────────────────
ERRORS=0
for var in STATUS_FIELD_ID DUE_FIELD_ID EPIC_FIELD_ID STATUS_IN_PROGRESS STATUS_BACKLOG EPIC_FRAMEWORK; do
  val="${!var}"
  if [ -z "$val" ]; then
    echo "❌ $var is empty — printing all field/option names found:"
    echo "$FIELDS_JSON" | jq -r '.[] | "  Field: \(.name // "(no name)")" + if .options then ("\n" + (.options[] | "    Option: \(.name) [\(.id)]")) else "" end'
    ERRORS=1
  fi
done
[ "$ERRORS" -eq 1 ] && exit 1

# ─── HELPERS ───────────────────────────────────────────────────────────────────

# Creates an issue; sets globals ISSUE_NUMBER and ISSUE_NODE_ID
# Usage: create_issue "<title>" "<body>" [assignee1] [assignee2] ...
create_issue() {
  local title=$1 body=$2
  shift 2
  local args=(--repo "$REPO" --title "$title" --body "$body")
  for a in "$@"; do
    args+=(--assignee "$a")
  done
  local url
  url=$(gh issue create "${args[@]}") || { echo "   ❌ create_issue failed for: $title"; exit 1; }
  ISSUE_NUMBER=$(echo "$url" | tr -d '\r' | grep -o '[0-9]*$')
  if [ -z "$ISSUE_NUMBER" ]; then
    echo "   ❌ Could not extract issue number from URL: $url"
    exit 1
  fi
  ISSUE_NODE_ID=$(gh api "repos/$REPO/issues/$ISSUE_NUMBER" --jq '.node_id' | tr -d '\r')
}

# Adds an issue (by node ID) to the project; returns the project item ID
add_to_project() {
  local node_id=$1
  local out item_id
  out=$(gh api graphql -f query='
    mutation($pid: ID!, $cid: ID!) {
      addProjectV2ItemById(input: { projectId: $pid, contentId: $cid }) {
        item { id }
      }
    }' -f pid="$PROJECT_ID" -f cid="$node_id" 2>&1) || { echo "   ❌ add_to_project failed: $out"; exit 1; }
  item_id=$(echo "$out" | jq -r '.data.addProjectV2ItemById.item.id')
  if [ -z "$item_id" ] || [ "$item_id" = "null" ]; then
    echo "   ❌ add_to_project returned empty item ID. node_id=$node_id response=$out"
    exit 1
  fi
  echo "$item_id"
}

# Sets a Single Select field on a project item
set_single_select() {
  local item_id=$1 field_id=$2 option_id=$3
  local out
  out=$(gh api graphql -f query='
    mutation($pid: ID!, $iid: ID!, $fid: ID!, $oid: String!) {
      updateProjectV2ItemFieldValue(input: {
        projectId: $pid, itemId: $iid, fieldId: $fid,
        value: { singleSelectOptionId: $oid }
      }) { projectV2Item { id } }
    }' -f pid="$PROJECT_ID" -f iid="$item_id" -f fid="$field_id" \
       -f oid="$option_id" 2>&1) || echo "   ⚠️  set_single_select failed (field=$field_id option=$option_id): $out"
}

# Sets a Date field on a project item
set_date() {
  local item_id=$1 field_id=$2 date_val=$3
  local out
  out=$(gh api graphql -f query='
    mutation($pid: ID!, $iid: ID!, $fid: ID!, $date: Date!) {
      updateProjectV2ItemFieldValue(input: {
        projectId: $pid, itemId: $iid, fieldId: $fid,
        value: { date: $date }
      }) { projectV2Item { id } }
    }' -f pid="$PROJECT_ID" -f iid="$item_id" -f fid="$field_id" \
       -f date="$date_val" 2>&1) || echo "   ⚠️  set_date failed (field=$field_id date=$date_val): $out"
}

# Links a child issue as a sub-issue of a parent
link_sub_issue() {
  local parent_num=$1 child_num=$2
  local child_id out
  child_id=$(gh api "repos/$REPO/issues/$child_num" --jq '.id' | tr -d '\r')
  out=$(gh api -X POST \
    -H "GraphQL-Features: sub_issues" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "repos/$REPO/issues/$parent_num/sub_issues" \
    -F "sub_issue_id=$child_id" 2>&1) || echo "   ⚠️  link_sub_issue failed (#$parent_num -> #$child_num id=$child_id): $out"
}

# ─── IMPORT ────────────────────────────────────────────────────────────────────
# echo ""
# echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# echo "Starting import: 9 parent issues, 29 sub-issues"
# echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# # ── [1/9] Helix - Agentic Delivery Introduction ────────────────────────────────
# echo ""
# echo "🟦 [1/9] [FEATURE] Helix - Agentic Delivery Introduction"
# create_issue \
#   "[FEATURE] Helix - Agentic Delivery Introduction" \
#   "Deliverable - Website"
# PARENT_1_NUM=$ISSUE_NUMBER
# ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
# set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
# set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
# echo "   ✅ Created #$PARENT_1_NUM"

# # ── [2/9] Helix - Agentic Delivery Framework ───────────────────────────────────
# echo ""
# echo "🟦 [2/9] [FEATURE] Helix - Agentic Delivery Framework"
# create_issue \
#   "[FEATURE] Helix - Agentic Delivery Framework" \
#   "Deliverable - Website / PPT"
# PARENT_2_NUM=$ISSUE_NUMBER
# ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
# set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
# set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
# echo "   ✅ Created #$PARENT_2_NUM"

# # ── [3/9] Helix - Discovery - Assess Readiness ────────────────────────────────
# echo ""
# echo "🟦 [3/9] [FEATURE] Helix - Discovery - Assess Readiness"
# create_issue \
#   "[FEATURE] Helix - Discovery - Assess Readiness" \
#   "[FEATURE] Helix - Discovery - Assess Readiness"
# PARENT_3_NUM=$ISSUE_NUMBER
# ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
# set_single_select "$ITEM_ID" "$EPIC_FIELD_ID" "$EPIC_FRAMEWORK"
# echo "   ✅ Created #$PARENT_3_NUM"

#   echo "   🔹 Sub-issue: Helix - PM Domain discovery"
#   create_issue \
#     "Helix - PM Domain discovery (include domain expert discovery)" \
#     "Deliverable - Workshop Templates (pain points, scoping, requirements)" \
#     "AIS-John-Connolly"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-03"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_3_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - Define User Acceptance Criteria"
#   create_issue \
#     "Helix - Define User Acceptance Criteria" \
#     "Deliverable - Document"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-03"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_3_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

# # ── [4/9] Helix - Design ──────────────────────────────────────────────────────
# echo ""
# echo "🟦 [4/9] [FEATURE] Helix - Design"
# create_issue \
#   "[FEATURE] Helix - Design" \
#   "This milestone establishes the foundational understanding of the business domain and translates it into a structured, agent‑ready software design.
# It focuses on deep discovery, domain modeling, and creating the architectural blueprint that will guide all downstream agentic development."
# PARENT_4_NUM=$ISSUE_NUMBER
# ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
# set_single_select "$ITEM_ID" "$EPIC_FIELD_ID" "$EPIC_FRAMEWORK"
# echo "   ✅ Created #$PARENT_4_NUM"

#   echo "   🔹 Sub-issue: Helix - PM EventStorming - Big Picture"
#   create_issue \
#     "Helix - PM EventStorming - Big Picture" \
#     "Deliverable - Lucid Chart" \
#     "AIS-John-Connolly"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-03-30"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_4_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - PM EventStorming - Process Modeling"
#   create_issue \
#     "Helix - PM EventStorming - Process Modeling" \
#     "Deliverable - Lucid Chart" \
#     "AIS-John-Connolly"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-03-30"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_4_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - PM Context mapping"
#   create_issue \
#     "Helix - PM Context mapping" \
#     "Deliverable - Lucid Chart" \
#     "AIS-John-Connolly"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-03-30"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_4_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - PM EventStorming - Software Design"
#   create_issue \
#     "Helix - PM EventStorming - Software Design" \
#     "Deliverable - Lucid Chart" \
#     "AIS-John-Connolly" "kcjonesevans"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_BACKLOG"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-03-30"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_4_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - PM Design per context"
#   create_issue \
#     "Helix - PM Design per context" \
#     "Deliverable - Figma" \
#     "kcjonesevans"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_BACKLOG"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-10"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_4_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - PM Database Design per context"
#   create_issue \
#     "Helix - PM Database Design per context" \
#     "Deliverable - SQL" \
#     "nasirmirzagit"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_BACKLOG"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-10"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_4_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

# # ── [5/9] Helix - Design to Develop contract ──────────────────────────────────
# echo ""
# echo "🟦 [5/9] [FEATURE] Helix - Design to Develop contract"
# create_issue \
#   "[FEATURE] Helix - Design to Develop contract" \
#   "This milestone formalizes the handoff between design and development by producing structured, machine‑readable assets that agentic developers can consume."
# PARENT_5_NUM=$ISSUE_NUMBER
# ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
# set_single_select "$ITEM_ID" "$EPIC_FIELD_ID" "$EPIC_FRAMEWORK"
# echo "   ✅ Created #$PARENT_5_NUM"

#   echo "   🔹 Sub-issue: Helix - Design Software Design CSV"
#   create_issue \
#     "Helix - Design Software Design CSV" \
#     "Deliverable - CSV" \
#     "AIS-John-Connolly" "kcjonesevans"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-07"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_5_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - Design Markdown template"
#   create_issue \
#     "Helix - Design Markdown template" \
#     "Deliverable - MD" \
#     "AIS-John-Connolly" "kcjonesevans"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-07"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_5_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - Design Prompt"
#   create_issue \
#     "Helix - Design Prompt" \
#     "Deliverable - txt"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-07"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_5_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - Design UI Assets"
#   create_issue \
#     "Helix - Design UI Assets" \
#     "Deliverable - Figma"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_BACKLOG"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-14"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_5_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - Design Database Scripts"
#   create_issue \
#     "Helix - Design Database Scripts" \
#     "Deliverable - SQL" \
#     "nasirmirzagit"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_BACKLOG"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-14"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_5_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

# # ── [6/9] Helix - Client Agentic Enablement (Optional) ────────────────────────
# echo ""
# echo "🟦 [6/9] [FEATURE] Helix - Client Agentic Enablement (Optional)"
# create_issue \
#   "[FEATURE] Helix - Client Agentic Enablement (Optional)" \
#   "This milestone prepares the client's engineering team to work effectively with agentic workflows and tools."
# PARENT_6_NUM=$ISSUE_NUMBER
# ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
# set_single_select "$ITEM_ID" "$EPIC_FIELD_ID" "$EPIC_FRAMEWORK"
# echo "   ✅ Created #$PARENT_6_NUM"

#   echo "   🔹 Sub-issue: Helix - Setup Client Developers"
#   create_issue \
#     "Helix - Setup Client Developers" \
#     "Deliverable - Document; People Enablement"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_BACKLOG"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-14"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_6_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

# # ── [7/9] Helix - Develop ────────────────────────────────────────────────────
# echo ""
# echo "🟦 [7/9] [FEATURE] Helix - Develop"
# create_issue \
#   "[FEATURE] Helix - Develop" \
#   "This milestone executes the agent‑driven development process, combining automated generation with human‑in‑the‑loop oversight."
# PARENT_7_NUM=$ISSUE_NUMBER
# ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
# set_single_select "$ITEM_ID" "$EPIC_FIELD_ID" "$EPIC_FRAMEWORK"
# echo "   ✅ Created #$PARENT_7_NUM"

#   echo "   🔹 Sub-issue: Helix - Design Architectural Instructions"
#   create_issue \
#     "Helix - Design Architectural Instructions" \
#     "Deliverable - MD" \
#     "dracman65" "steven-suing"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-14"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_7_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - PM Agentic Infrastructure Setup"
#   create_issue \
#     "Helix - PM Agentic Infrastructure Setup" \
#     "Deliverable - Agents, settings" \
#     "kcjonesevans" "nasirmirzagit"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-14"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_7_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - PM Agentic Development (includes data/UI/LLMs)"
#   create_issue \
#     "Helix - PM Agentic Development (includes data/UI/LLMs)" \
#     "Deliverable - Code files" \
#     "kcjonesevans" "nasirmirzagit"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-14"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_7_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - PM Agentic Testing / troubleshooting"
#   create_issue \
#     "Helix - PM Agentic Testing / troubleshooting" \
#     "Deliverable - Code files"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-14"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_7_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - PM Agentic Pull Requests"
#   create_issue \
#     "Helix - PM Agentic Pull Requests" \
#     "Deliverable - GitHub" \
#     "kcjonesevans"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-14"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_7_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - PM Agentic Integration Contracts between contexts"
#   create_issue \
#     "Helix - PM Agentic Integration Contracts between contexts" \
#     "Deliverable - Code files"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
#   set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-14"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_7_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

#   echo "   🔹 Sub-issue: Helix - PM Telemetry - Application"
#   create_issue \
#     "Helix - PM Telemetry - Application" \
#     "Helix - PM Telemetry - Application"
#   ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
#   set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_BACKLOG"
#   set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
#   link_sub_issue "$PARENT_7_NUM" "$ISSUE_NUMBER"
#   echo "      ✅ Created #$ISSUE_NUMBER"

# # ── [8/9] Helix - Develop to Deliver contract ─────────────────────────────────
# echo ""
# echo "🟦 [8/9] [FEATURE] Helix - Develop to Deliver contract"
# create_issue \
#   "[FEATURE] Helix - Develop to Deliver contract" \
#   "This milestone defines the operational and deployment‑ready assets required to move the solution into delivery." \
#   "AIS-John-Connolly" "kcjonesevans" "dracman65"
# PARENT_8_NUM=$ISSUE_NUMBER
# ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
# set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_BACKLOG"
# set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-10"
# set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
# echo "   ✅ Created #$PARENT_8_NUM"

# ── [9/9] Helix - Deliver ────────────────────────────────────────────────────
echo ""
echo "🟦 [9/9] [FEATURE] Helix - Deliver"
create_issue \
  "[FEATURE] Helix - Deliver" \
  "This milestone operationalizes the solution, ensuring it is deployed, validated, and ready for production use."
PARENT_9_NUM=$ISSUE_NUMBER
ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
echo "   ✅ Created #$PARENT_9_NUM"

  echo "   🔹 Sub-issue: Helix - PM Environment Provisioning"
  create_issue \
    "Helix - PM Environment Provisioning" \
    "GitHub" \
    "dracman65"
  ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
  set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
  set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-10"
  set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
  link_sub_issue "$PARENT_9_NUM" "$ISSUE_NUMBER"
  echo "      ✅ Created #$ISSUE_NUMBER"

  echo "   🔹 Sub-issue: Helix - PM Application deployment"
  create_issue \
    "Helix - PM Application deployment" \
    "GitHub" \
    "dracman65"
  ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
  set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_BACKLOG"
  set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-10"
  set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
  link_sub_issue "$PARENT_9_NUM" "$ISSUE_NUMBER"
  echo "      ✅ Created #$ISSUE_NUMBER"

  echo "   🔹 Sub-issue: Helix - PM Observability"
  create_issue \
    "Helix - PM Observability" \
    "Helix - PM Observability"
  ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
  set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
  set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-14"
  set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
  link_sub_issue "$PARENT_9_NUM" "$ISSUE_NUMBER"
  echo "      ✅ Created #$ISSUE_NUMBER"

  echo "   🔹 Sub-issue: Helix - PM QA/ Validation"
  create_issue \
    "Helix - PM QA/ Validation" \
    "GitHub" \
    "dracman65"
  ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
  set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_BACKLOG"
  set_date          "$ITEM_ID" "$DUE_FIELD_ID"    "2026-04-10"
  set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
  link_sub_issue "$PARENT_9_NUM" "$ISSUE_NUMBER"
  echo "      ✅ Created #$ISSUE_NUMBER"

  echo "   🔹 Sub-issue: Helix - Design UAT"
  create_issue \
    "Helix - Design UAT" \
    "Helix - Design UAT"
  ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
  set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_IN_PROGRESS"
  set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
  link_sub_issue "$PARENT_9_NUM" "$ISSUE_NUMBER"
  echo "      ✅ Created #$ISSUE_NUMBER"

  echo "   🔹 Sub-issue: Helix - PM Final Deliverable to Prod"
  create_issue \
    "Helix - PM Final Deliverable to Prod" \
    "Helix - PM Final Deliverable to Prod"
  ITEM_ID=$(add_to_project "$ISSUE_NODE_ID")
  set_single_select "$ITEM_ID" "$STATUS_FIELD_ID" "$STATUS_BACKLOG"
  set_single_select "$ITEM_ID" "$EPIC_FIELD_ID"   "$EPIC_FRAMEWORK"
  link_sub_issue "$PARENT_9_NUM" "$ISSUE_NUMBER"
  echo "      ✅ Created #$ISSUE_NUMBER"

# ─── DONE ─────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Import complete! 9 parents · 29 sub-issues"
echo "   View at: https://github.com/orgs/AIS-Commercial-Business-Unit/projects/1/views/1"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
