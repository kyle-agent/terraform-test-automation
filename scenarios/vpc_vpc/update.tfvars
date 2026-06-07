# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Mutates only the VPC description (Optional+Computed, no RequiresReplace; the
# provider's vpcVpcResource.Update PATCHes it in place). Re-apply must succeed
# and the following re-plan must be a clean no-op. cidr/name are left unchanged
# so no replacement is triggered. Kept within the schema's maxLength of 50.
vpc_description = "regr-test updated"
