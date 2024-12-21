
variable "vpc_id" {
  type = string
}

variable "proxy_service_name" {
  type = string
  default = "codeartifact-proxy-service"
}

variable "ecs_task_role_prefix" {
  type = string
  default = "CodeArtifactProxyTaskRole"
}

variable "proxy_task_name" {
  type = string
  default = "codeartifact-proxy-task"
}

variable "proxy_port" {
  type = number
  default = 5000
}

variable "username" {
  type = string
  default = null
  sensitive = true
}

variable "password" {
  type = string
  default = null
  sensitive = true
}

variable "allow_anonymous_access" {
  type = bool
  default = false
}

variable "proxy_image_tag" {
  type = string
  default = "latest"
}

variable "create_cluster" {
  type = bool
  default = true
  description = "Create a new ECS cluster for the proxy service."
}

variable "cluster_name" {
  type = string
  default = "codeartifact-proxy-cluster"
}

variable "service_tags" {
  type = map(string)
  default = {}
}

variable "task_tags" {
  type = map(string)
  default = {}
}

variable "cluster_tags" {
  type = map(string)
  default = {}
}

variable "codeartifact_region" {
  type = string
  default = null
  description = "If null, defaults to this region."
}

variable "codeartifact_domain" {
  type = string
}

variable "codeartifact_repository" {
  type = string
}

variable "codeartifact_account_id" {
  type = string
  default = null
  description = "If null, defaults to the account ID of the current user."
}

variable "task_cpu" {
  type = number
  default = 256
}

variable "task_memory" {
  type = number
  default = 512
}

variable "task_replicas" {
  type = number
  default = 1
}

variable "code_artifact_policy" {
  type = string
  default = null
  description = "Defaults to full access for the designated domain and repository."
}