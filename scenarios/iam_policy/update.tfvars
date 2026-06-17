# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Mutates only the policy description (Optional, in-place updatable — not
# RequiresReplace). The provider's iam policy Update must PATCH it in place, so
# the re-apply must succeed and the subsequent re-plan must be a clean no-op.
# policy_name / policy_resource are left unchanged so no replacement is triggered.
policy_description = "regr iam policy (updated)"
