# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Log group name is RequiresReplace; retention_period is Required and
# in-place-updatable via UpdateLogGroup. Mutating it must re-apply cleanly and
# re-plan as a no-op.
log_group_retention_period = 60
