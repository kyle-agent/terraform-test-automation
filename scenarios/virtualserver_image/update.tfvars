# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# The image has no description; tags are in-place-updatable via handlerUpdateTag. Mutating the tag map must re-apply cleanly and re-plan as a no-op.
image_tags = { "regr" = "terraform-updated" }
