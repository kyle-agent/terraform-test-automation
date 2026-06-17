# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# The dashboard has no description; name is the only user-settable attribute and
# is in-place-updatable via UpdateDashboard (Optional, no RequiresReplace).
# Mutating it must re-apply cleanly and re-plan as a no-op.
dashboard_name = "regr-dashboard-updated"
