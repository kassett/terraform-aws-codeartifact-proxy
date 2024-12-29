
locals {
  # DO NOT EDIT
  TRACKED_GIT_VERSION = "0.1.28"
  image_name              = "codeartifact-proxy"
  image_repository        = "kassett247"
}

locals {
  # Necessary because we need ot give access to create a bearer token for this domain
  unique_domains = tolist(toset([ for hos in var.repositories : hos.domain ]))
  image_tag               = coalesce(var.image_tag, local.TRACKED_GIT_VERSION)
}

data "aws_region" "this" {}
data "aws_caller_identity" "this" {}

check "unique_domains" {
  assert {
    condition = length(var.repositories) ==
    length(toset([ for hos in var.repositories : hos.hostname]))
    error_message = "There must be a unique hostname for each repository."
  }

  assert {
    condition = length(concat([ for hos in var.repositories: hos.additional_hosts ])) ==
    length(tolist(toset(concat([ for hos in var.repositories: hos.additional_hosts ]))))
    error_message = "There must be unique additional hosts for each repository."
  }
}

check "supported_package_managers" {
  assert {
    condition = alltrue([ for hos in var.repositories : contains(["npm", "pypi", "maven"], hos.package_manager)])
    error_message = "The package manager must be one of 'npm', 'pypi', or 'maven'."
  }
}

# Validation that all domains and repositories exist
# Also validates that the format -- i.e. the package manager -- provided is valid
data "aws_codeartifact_repository_endpoint" "repository" {
  count = length(var.repositories)
  domain     = var.repositories[count.index].domain
  format     = var.repositories[count.index].package_manager
  repository = var.repositories[count.index].repository
}

resource "aws_cloudwatch_log_group" "lg" {
  name = var.names.log_group
}

resource "aws_secretsmanager_secret" "auth" {
  count       = var.authentication.allow_anonymous ? 0 : 1
  name_prefix = var.names.secret_prefix
}

resource "aws_secretsmanager_secret_version" "auth" {
  count     = var.authentication.allow_anonymous ? 0 : 1
  secret_id = aws_secretsmanager_secret.auth[0].id
  secret_string = jsonencode({
    username = var.authentication.username
    password = var.authentication.password
  })
}

resource "aws_security_group" "sg" {
  count       = length(var.networking.security_groups) == 0 ? 1 : 0
  vpc_id      = var.networking.vpc_id
  name_prefix = var.names.security_group_prefix
  description = "Default security group created to give access to the CodeArtifact Proxy."
}

resource "aws_vpc_security_group_egress_rule" "internet_access" {
  count = length(var.networking.security_groups) == 0 ? 1 : 0
  security_group_id = aws_security_group.sg[0].id
  ip_protocol = "-1"
  cidr_ipv4 = "0.0.0.0/0"
}

locals {
  security_groups = length(var.networking.security_groups) > 0 ? var.networking.security_groups : [try(aws_security_group.sg[0].id)]
}
