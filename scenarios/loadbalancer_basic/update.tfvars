# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Mutates only the LB description (loadbalancer_create.description, Optional, no
# RequiresReplace; the provider's UpdateLoadbalancer PATCHes it in place). Re-apply
# must succeed and the following re-plan must be a clean no-op.
lb_description = "regr-test lb updated"
