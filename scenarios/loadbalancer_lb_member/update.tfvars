# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# The member has no description; member_weight (1-1000, Optional, no RequiresReplace)
# is patched in place by the provider's UpdateLbMember. Bumping 1 -> 2 must re-apply
# cleanly and the following re-plan must be a clean no-op.
member_weight = 2
