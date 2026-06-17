# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# The server has no description; tags are in-place-updatable via the provider's
# handlerUpdateTag (not in the immutable field list). Mutating the tag map must
# re-apply cleanly and re-plan as a no-op.
tags = { "regr" = "terraform-updated" }
