
# CodeArtifact Proxy

CodeArtifact is a good option for a private artifact repository, but authentication
can be difficult to integrate with CI/CD and containerization. Adding AWS
credentials to Dockerfiles is not a good option, passing normally obfuscated config
files to containers can be tedious, etc. In many cases, it may be easier
to just use a VPN or security group rules for everyday use. This tool allows you to do that.

### Current support
Currently, there is only support for acting as a PyPI server, but NPM, Yarn, and Maven
will be pushed soon.

### Required permissions
If you wish to attach custom permissions to the ECS task, you can use the `codeartifact_policy` argument.
By default, the CodeArtifact Proxy container is given 3 permissions:
* Full access to specified CodeArtifact repository
* Access to create a bearer token to specified domain
* Access to create log streams and put logs to the specified log group

### Authentication
The proxy container can either be accessed anonymously or via username-password
authentication. Using basic authentication will create an AWS secret. The secret id
is specified in the task definition environment variables and pulled into
the container on startup. This means that changing the username/password will 
require the tasks to be restarted.

### Hosting
Specifying the hosting variable object will trigger the creation of a load balancer, 
load balancer listener, target group, route, and certificate. The certificate
will be validated automatically and the record is a CNAME record.

### Environment variables
The following environment variables are exposed in the Docker container

| Environment Variable         | Default Value           | Terraform Variable                                    |
|------------------------------|-------------------------|-------------------------------------------------------|
| `PROXY_REGION`               | `null`                  | `repository_settings.region`                          |
| `PROXY_ACCOUNT_ID`           | `null`                  | `repository_settings.account_id`                      |
| `PROXY_DOMAIN`               | `null`                  | `repository_settings.domain`                          |
| `PROXY_REPOSITORY`           | `null`                  | `repository_settings.repository`                      |
| `PROXY_SECRET_ID`            | `null`                  | `authentication.username && authentication.password`  |
| `PROXY_ALLOW_ANONYMOUS`      | `null`                  | `authentication.allow_anonymous`                      |
| `PROXY_SERVER_PORT`          | `5000`                  | `networking.container_port`                           |
| `PROXY_HEALTH_CHECK_PATH`    | `/health`               | `var.networking.health_check.path`                    |

### Examples

```terraform
# Example minimal usage
module "codeartifact-proxy" {
  repository_settings = {
    domain = aws_codeartifact_domain.pypi.domain
    repository = aws_codeartifact_repository.pypi.repository
  }
  
  networking = {
    vpc_id = "VPC_ID"
    subnets = ["PRIVATE_SUBNET", "PRIVATE_SUBNET"]
  }

  hosting = {
    zone_name = "example.com"
    record_name = "pypi"
  }

  authentication = {
    allow_anonymous = true
  }
}
```

```terraform
# Example extended configuration
module "codeartifact-proxy" {
  repository_settings = {
    domain = aws_codeartifact_domain.pypi.domain
    repository = aws_codeartifact_repository.pypi.repository
  }
  
  names = {
    service = "cd-proxy"
  }

  networking = {
    vpc_id = "VPC_ID"
    subnets = ["PRIVATE_SUBNET", "PRIVATE_SUBNET"]
    health_check = {
      timeout = 1
      interval = 30
    }
  }

  tags = {
    service = {
      SERVICE_TAG = "SERVICE_TAG_VALUE"
    }
  }

  hosting = {
    zone_name = "example.com"
    record_name = "pypi"
  }

  authentication = {
    username = "USERNAME"
    password = "PASSWORD"
  }
}
```
