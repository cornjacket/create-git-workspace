#!/usr/bin/env bash
# Shared helper functions for pipeline-subtask task.json operations.
# Source this file in scripts that create or complete pipeline subtasks.
#
# All JSON operations use Python3 (always available — orchestrator requires it).
#
# Functions:
#   is_pipeline_task <task-dir>                          — returns 0 if task.json exists
#   json_get <json-file> <field>                         — prints field value
#   json_set_str <json-file> <field> <value>             — sets string field
#   json_set_bool <json-file> <field> true|false         — sets boolean field
#   get_and_increment_subtask_id <json-file>             — prints current 4-digit ID, increments
#   json_append_subtask <json-file> <subtask-dir-name>   — appends {name, complete:false}
#   json_complete_subtask <json-file> <subtask-dir-name> — sets complete:true for matching name
#   json_next_subtask <json-file>                        — prints first incomplete subtask name
#   json_subtasks_complete <json-file>                   — exit 0 if all complete
#   get_parent_short_id <dir>                            — extracts 6-char hex prefix from basename

# Cross-platform in-place sed. BSD sed (macOS) requires an empty-string argument
# after -i; GNU sed (Linux) does not. Use this wrapper instead of `sed -i ''`.
_sed_i() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Returns 0 if the given directory contains a task.json (i.e. it's a pipeline task).
is_pipeline_task() {
    local task_dir="$1"
    [[ -f "$task_dir/task.json" ]]
}

# Print the value of a JSON field.
# Booleans print as "true" or "false"; null/missing prints as "".
json_get() {
    local json_file="$1"
    local field="$2"
    python3 - "$json_file" "$field" <<'EOF'
import sys, json
data = json.load(open(sys.argv[1]))
val = data.get(sys.argv[2])
if val is None:
    print("")
elif isinstance(val, bool):
    print("true" if val else "false")
else:
    print(val)
EOF
}

# Set a string field in a JSON file (in-place).
json_set_str() {
    local json_file="$1"
    local field="$2"
    local value="$3"
    python3 - "$json_file" "$field" "$value" <<'EOF'
import sys, json
path, field, value = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(path))
data[field] = value
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
EOF
}

# Set a boolean field in a JSON file (in-place).
json_set_bool() {
    local json_file="$1"
    local field="$2"
    local value="$3"  # "true" or "false"
    python3 - "$json_file" "$field" "$value" <<'EOF'
import sys, json
path, field, value = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(path))
data[field] = (value == "true")
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
EOF
}

# Print the current 4-digit Next-subtask-id and increment it in task.json.
get_and_increment_subtask_id() {
    local json_file="$1"
    python3 - "$json_file" <<'EOF'
import sys, json
path = sys.argv[1]
data = json.load(open(path))
current = data.get("next-subtask-id", "0000")
print(current)
next_id = "%04d" % (int(current, 10) + 1)
data["next-subtask-id"] = next_id
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
EOF
}

# Append a new subtask entry {name, complete:false} to the subtasks array.
json_append_subtask() {
    local json_file="$1"
    local subtask_name="$2"
    python3 - "$json_file" "$subtask_name" <<'EOF'
import sys, json
path, name = sys.argv[1], sys.argv[2]
data = json.load(open(path))
if "subtasks" not in data:
    data["subtasks"] = []
data["subtasks"].append({"name": name, "complete": False})
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
EOF
}

# Mark a subtask entry as complete:true in the subtasks array.
json_complete_subtask() {
    local json_file="$1"
    local subtask_name="$2"
    python3 - "$json_file" "$subtask_name" <<'EOF'
import sys, json
path, name = sys.argv[1], sys.argv[2]
data = json.load(open(path))
for entry in data.get("subtasks", []):
    if entry.get("name") == name:
        entry["complete"] = True
        break
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
EOF
}

# Print the name of the first incomplete subtask. Exit 1 if none.
json_next_subtask() {
    local json_file="$1"
    python3 - "$json_file" <<'EOF'
import sys, json
data = json.load(open(sys.argv[1]))
for entry in data.get("subtasks", []):
    if not entry.get("complete", False):
        print(entry["name"])
        sys.exit(0)
sys.exit(1)
EOF
}

# Exit 0 if all subtasks are complete (or there are none). Exit 1 otherwise.
json_subtasks_complete() {
    local json_file="$1"
    python3 - "$json_file" <<'EOF'
import sys, json
data = json.load(open(sys.argv[1]))
for entry in data.get("subtasks", []):
    if not entry.get("complete", False):
        sys.exit(1)
sys.exit(0)
EOF
}

# Extract the 6-char hex short ID (first dash-delimited segment) from a directory basename.
get_parent_short_id() {
    local parent_dir="$1"
    basename "$parent_dir" | cut -d'-' -f1
}
