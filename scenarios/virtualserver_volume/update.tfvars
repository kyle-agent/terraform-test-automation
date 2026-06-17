# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# The volume has no description; tags are in-place-updatable via tag.UpdateTags
# in the volume Update path (preferred over the riskier size-grow path).
# Mutating the tag map must re-apply cleanly and re-plan as a no-op.
tags = { "regr" = "terraform-updated" }
