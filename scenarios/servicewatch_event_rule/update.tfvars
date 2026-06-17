# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Mutates the event rule's description, sent in-place via UpdateEventRule
# (Optional, no RequiresReplace). Re-apply must succeed and the subsequent
# re-plan be a clean no-op.
event_rule_description = "Regression fixture: ServiceWatch event rule (updated)."
