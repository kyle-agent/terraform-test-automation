# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Mutates only a safe, in-place-updatable attribute (description) of the
# security group. The provider's securityGroupResource.Update updates the
# description without RequiresReplace, so a re-apply must succeed and the
# subsequent re-plan must be clean (idempotent). A spurious destroy+create or a
# non-converging update here is an in-place Update defect (cf. provider #71/#72).
description = "regression test sg (updated)"
