
variable "networking" {
  type = object({
    vpc_id          = string
    subnets         = list(string)
    security_groups = optional(list(string), [])
    host_port       = optional(number, 5000)
    container_port  = optional(number, 5000)
  })
}

variable "names" {
  type = object({
    service               = optional(string, "codeartifact-proxy-service")
    security_group_prefix = optional(string, "codeartifact-proxy-security-group")
    cluster               = optional(string, "codeartifact-proxy-cluster")
    role_prefix           = optional(string, "CodeArtifactProxyRole")
    task_definition       = optional(string, "codeartifact-proxy-task-definition")
    log_group             = optional(string, "/ecs/codeartifact-proxy")
  })
  default = {}
}

variable "authentication" {
  type = object({
    username        = optional(string)
    password        = optional(string)
    allow_anonymous = optional(bool)
  })
}

variable "tags" {
  type = object({
    service         = optional(map(string))
    cluster         = optional(map(string))
    role            = optional(map(string))
    task_definition = optional(map(string))
    security_group  = optional(map(string))
  })
  default = {}
}

variable "create_cluster" {
  type    = bool
  default = true
}

variable "repository_settings" {
  type = object({
    region     = optional(string)
    domain     = string
    repository = string
    account_id = optional(string)
  })
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}

variable "replicas" {
  type    = number
  default = 1
}

variable "code_artifact_policy" {
  type        = string
  default     = null
  description = "Defaults to full access for the designated domain and repository."
}

variable "image_tag" {
  type        = string
  default     = null
  description = "Defaults to the same tag version as the Terraform module."
}