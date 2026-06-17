# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Tags are in-place-updatable (tag.ResourceSchema is Optional, no RequiresReplace;
# the SKE cluster Update PATCHes via syncTags -> tag.UpdateTags, then waits for the
# cluster to return to RUNNING). Re-apply must succeed and re-plan clean.
tags = { env = "regression-updated" }
