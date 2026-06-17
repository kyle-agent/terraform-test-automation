# Capability-matrix optional "update" stage (MATRIX_UPDATE=1). Mutates only the
# hosted-zone description, the sole field the provider's Update accepts in place
# (checkModifiedFieldsExcludingDescription); re-apply succeeds, re-plan no-ops.
hz_description = "regr hosted zone (updated)"
