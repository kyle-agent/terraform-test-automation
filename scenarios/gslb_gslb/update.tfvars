# Capability-matrix optional "update" stage (MATRIX_UPDATE=1). Mutates only the
# GSLB description (Optional, no RequiresReplace; gslbChanged -> UpdateGslb);
# re-apply succeeds and the subsequent re-plan is a clean no-op.
gslb_description = "regr gslb (updated)"
