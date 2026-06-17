# Capability-matrix optional "update" stage (MATRIX_UPDATE=1). Mutates only the
# trail description (provider Update -> SetTrail, no RequiresReplace); re-apply
# succeeds and the subsequent re-plan is a clean no-op. bucket/name unchanged.
trail_description = "regr audit trail (updated)"
