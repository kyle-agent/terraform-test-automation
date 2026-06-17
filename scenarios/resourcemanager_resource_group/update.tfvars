# Capability-matrix optional "update" stage (MATRIX_UPDATE=1). Mutates only the
# resource-group description (Optional, no RequiresReplace; provider Update ->
# UpdateResourceGroup); re-apply succeeds and the re-plan is a clean no-op.
group_description = "regr resource group (updated)"
