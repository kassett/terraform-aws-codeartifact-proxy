
variable "replicas" {
  type    = number
  default = 1
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}

variable "names" {
  type = object({
    service                           = optional(string, "cap-service")
    security_group_prefix             = optional(string, "cap-sg")
    cluster                           = optional(string, "cap-cluster")
    role_prefix                       = optional(string, "CodeArtifactProxyRole")
    secret_prefix                     = optional(string, "cap-auth-secret")
    task_definition                   = optional(string, "cap-td")
    log_group                         = optional(string, "/ecs/codeartifact-proxy")
    load_balancer_target_group_prefix = optional(string, "cap-tg")
    load_balancer_prefix              = optional(string, "cap-lb")
  })
  default = {}
}

variable "tags" {
  type = object({
    service                    = optional(map(string))
    cluster                    = optional(map(string))
    role                       = optional(map(string))
    certificate                = optional(map(string))
    secret                     = optional(map(string))
    task_definition            = optional(map(string))
    security_group             = optional(map(string))
    log_group                  = optional(map(string))
    load_balancer_target_group = optional(map(string))
    load_balancer_listener     = optional(map(string))
    load_balancer              = optional(map(string))
  })
  default = {}
}

variable "authentication" {
  type = object({
    username        = optional(string)
    password        = optional(string)
    allow_anonymous = optional(bool)
  })

  validation {
    condition = (
      var.authentication.username != null &&
      var.authentication.password != null &&
      !var.authentication.allow_anonymous) || (
      var.authentication.username == null &&
      var.authentication.password == null &&
      var.authentication.allow_anonymous
    )
  }
  sensitive = true
}

variable "default_tags" {
  type = map(string)
  default = {}
  description = "Tags to be applied to every applicable resource."
}

variable "image_tag" {
  type = string
  default = null
  description = "If null, defaults to the current version of the Terraform module."
}

variable "repositories" {
  type = list(object({
    package_manager = string
    domain = string
    repository = string

    hostname = optional(string)
    zone_id = optional(string)
    managed_externally = optional(bool, false)

    # Additional hosts that might be used, perhaps from CloudFlare
    additional_hosts = optional(list(string), [])
  }))
}

variable "networking" {
  type = object({
    vpc_id          = string
    subnets         = list(string)
    security_groups = optional(list(string), [])
    container_port  = optional(number, 5000)
    load_balancer_arn = optional(string)

    health_check = optional(object({
      path                = optional(string, "/health")
      interval            = optional(number, 30)
      timeout             = optional(number, 5)
      healthy_threshold   = optional(number, 5)
      unhealthy_threshold = optional(number, 2)
    }), {})

    external_target_group_arn = optional(string)
  })
}

variable "ssl_policy" {
  type = string
  default = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}