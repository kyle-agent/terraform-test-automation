# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Mutates only the server-group description (lb_server_group_create.description,
# Optional, no RequiresReplace; the provider's UpdateLbServerGroup PATCHes it in
# place). Re-apply must succeed and the following re-plan must be a clean no-op.
server_group_description = "regr-test sg updated"
