
# check "hosting_or_external_target_group_arn" {
#   assert {
#     condition     = (tonumber(var.hosting != null) + tonumber((var.networking.external_target_group_arn != null))) < 2
#     error_message = "Either `var.hosting` or `var.networking.external_target_group_arn` can be defined, but not both."
#   }
# }
#
# check "authentication" {
#   assert {
#     condition     = (var.authentication.username != null && var.authentication.password != null) || var.authentication.allow_anonymous
#     error_message = "`var.authentication.username` and `var.authentication.password` must be defined together, or `var.authentication.allow_anonymous` must be true."
#   }
# }