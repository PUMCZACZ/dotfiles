#!/usr/bin/env python3
"""Small source-level adjustments to the pinned upstream extension after renaming tools."""
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
source = path.read_text()

# Do not give the model a copy/pastable placeholder follow-up instruction on
# *every* completion: it otherwise loops forever resuming an already-done child.
source, count = re.subn(r'  const sessionRef = `[^`]*`;', '  const sessionRef = "";', source)
assert count == 1, "upstream completion presentation changed"

old_import = '  readScreen,\n} from "./herdr.ts";'
assert source.count(old_import) == 1, "upstream surface import changed"
source = source.replace(old_import, '  readScreen,\n  findLiveSessionSurface,\n} from "./herdr.ts";')

# Reject unsupported CLIs before creating a Herdr pane or writing launch state.
anchor = '  const agentDefs = params.agent ? loadAgentDefaults(params.agent) : null;'
assert source.count(anchor) == 1, "upstream agent resolution changed"
source = source.replace(anchor, anchor + '\n  if (agentDefs?.cli === "claude") throw new Error("Only Pi subagents are supported by the Herdr profile");')

# The upstream map only tracks children launched in THIS Pi process. After a
# restart a previous child can still occupy a Herdr pane; opening the same
# JSONL in another Pi instance would corrupt its transcript.
anchor = '        const loadout = readSubagentLoadout(sessionPath);'
assert source.count(anchor) == 1, "upstream resume path changed"
source = source.replace(anchor, '''        const livePane = findLiveSessionSurface(sessionPath);
        if (livePane) {
          const err = `Subagent "${requestedName}" is still open in Herdr pane ${livePane}. ` +
            `Use that pane or close it before resuming this Pi session; concurrent writers are unsafe.`;
          return { content: [{ type: "text" as const, text: err }], details: { error: err, pane: livePane } };
        }
''' + anchor)
path.write_text(source)
