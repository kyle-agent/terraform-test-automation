# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Mutates only the health-check description (lb_health_check_create.description,
# Optional, no RequiresReplace; the provider's UpdateLbHealthCheck PATCHes it in
# place). Re-apply must succeed and the following re-plan must be a clean no-op.
health_check_description = "regr-test hc updated"
