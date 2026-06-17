# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Mutates the alert's description, which the provider updates in-place via
# UpdateAlertDescription (Optional, no RequiresReplace). Re-apply must succeed
# and the subsequent re-plan be a clean no-op.
alert_description = "Regression fixture: CPU utilization breach alert (updated)."
