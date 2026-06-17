# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Mutates only description, which UpdateVpnGateway PATCHes (no RequiresReplace); re-apply must be clean and re-plan a no-op.
gateway_description = "Regression VPN gateway fixture (updated)"
