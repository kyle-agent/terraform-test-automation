# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Mutates the firewall rule's description (firewall_rule_create.description),
# sent in-place via UpdateFirewallRule (Optional, no RequiresReplace, maxLength
# 100). Re-apply must succeed and the subsequent re-plan be a clean no-op.
firewall_rule_description = "regr-test (updated)"
