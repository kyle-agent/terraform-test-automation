# Capability-matrix optional "update" stage fixture (MATRIX_UPDATE=1).
# Tags are in-place-updatable (tag.ResourceSchema is Optional, no RequiresReplace;
# the cluster Update PATCHes via handlerUpdateTag -> tag.UpdateTags, a metadata-only
# change with no cluster modify/restart). Re-apply must succeed and re-plan clean.
tags = { "regr" = "terraform-updated" }
