# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# file_unit_recovery_enabled is Optional (no RequiresReplace) and is the only
# field the volume Update PATCHes (client.UpdateVolume sends just this flag; tags
# are NOT PATCHed on update). Flip false -> true; re-apply and re-plan clean.
file_unit_recovery_enabled = true
