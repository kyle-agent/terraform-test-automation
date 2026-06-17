# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Keypair name/public_key are immutable (Update rejects a Name change), so the
# only in-place-updatable attribute is tags. Mutating the tag map exercises
# tag.UpdateTags; the re-apply must succeed and the subsequent re-plan be clean.
tags = { "regr" = "terraform-updated" }
