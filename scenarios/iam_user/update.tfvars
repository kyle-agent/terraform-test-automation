# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Mutates only the user description (Optional, in-place updatable — not
# RequiresReplace). The provider's iam user Update must PATCH it in place, so
# the re-apply must succeed and the subsequent re-plan must be a clean no-op.
# user_name is left unchanged so no replacement is triggered.
user_description = "regr iam user (updated)"
