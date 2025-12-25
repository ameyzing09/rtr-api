# Workspace-specific variable overrides (if using Terraform workspaces)
# In ConnectX pattern, this file provides a way to override variables based on workspace
# For now, we're using separate environment folders instead of workspaces

# Example workspace-based configuration (if needed in future):
# locals {
#   workspace_config = {
#     dev = {
#       instance_type = "t3.micro"
#       min_capacity  = 1
#     }
#     ppe = {
#       instance_type = "t3.small"
#       min_capacity  = 2
#     }
#     prod = {
#       instance_type = "t3.medium"
#       min_capacity  = 3
#     }
#   }
#
#   current_config = local.workspace_config[terraform.workspace]
# }

# For now, all configuration is in environments/{env}/main.tf following ConnectX pattern
