# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Mutates only the Direct Connect description (Optional, maxLength 50, no
# RequiresReplace; the provider's UpdateDirectConnect PATCHes only this field).
# Re-apply must succeed and the following re-plan must be a clean no-op.
description = "regr-test DC updated"
