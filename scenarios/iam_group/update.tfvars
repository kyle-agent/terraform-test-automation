# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Mutates only the group description (Optional, in-place updatable — not
# RequiresReplace). The provider's iam group Update must PATCH it in place, so
# the re-apply must succeed and the subsequent re-plan must be a clean no-op.
# group_name is left unchanged so no replacement is triggered.
group_description = "regr iam group (updated)"
