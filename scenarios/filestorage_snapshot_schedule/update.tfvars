# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# snapshot_retention_count is Optional (no RequiresReplace) and is PATCHed by the
# schedule Update (client.UpdateSnapshotSchedule sends it; read back into state).
# Bump 4 -> 5 (within 1..128); re-apply must succeed and re-plan clean.
snapshot_retention_count = 5
