# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# is_enabled is the ONLY field UpdateAccessKey PATCHes (description is create-only),
# so disabling the key is the lone safe in-place update; re-apply must be clean and re-plan a no-op.
access_key_is_enabled = false
