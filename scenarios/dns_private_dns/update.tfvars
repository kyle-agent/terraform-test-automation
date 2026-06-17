# Capability-matrix optional "update" stage (MATRIX_UPDATE=1). Mutates only the
# private-DNS description (Optional, no RequiresReplace); re-apply succeeds and
# the subsequent re-plan is a clean no-op. name/connected_vpc_ids unchanged.
private_dns_description = "regr private DNS (updated)"
