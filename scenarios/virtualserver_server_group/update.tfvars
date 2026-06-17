# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Name and policy are immutable (Update rejects changes), so the only
# in-place-updatable attribute is tags. Mutating the tag map exercises
# tag.UpdateTags; the re-apply must succeed and the subsequent re-plan be clean.
tags = { "regr" = "terraform-updated" }
