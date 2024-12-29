
# CodeArtifact Proxy

CodeArtifact is a good option for a private artifact repository, but authentication
can be difficult to integrate with CI/CD and containerization. Adding AWS
credentials to Dockerfiles is not a good option, passing normally obfuscated config
files to containers can be tedious, etc. In many cases, it may be easier
to just use a VPN or security group rules for everyday use. This tool allows you to do that.

### Current support
Current support is for PYPI, NPM, and Maven. Yarn likely is also supported but hasn't been tested
thoroughly. NuGet, Cargo, and Ruby are on the roadmap.

### Current limitations
Scoped packages for NPM are currently not supported. This is next on the list.

### Required permissions
* Full access to specified CodeArtifact repositories and domains
* Access to create a bearer token to specified domain
* Access to create log streams and put logs to the specified log group

### Authentication
The proxy container can either be accessed anonymously or via username-password
authentication. Using basic authentication will create an AWS secret. The secret id
is specified in the task definition environment variables and pulled into
the container on startup. This means that changing the username/password will 
require the tasks to be restarted.

### Hosting
The domain / repository / format are identified by the hostname. Therefore, 
each host must be unique per `repository` object. These routes are secured with ACM,
but if you are using external certificates, there is an `additional_hosts` variable that can be added.

### Environment variables
The following environment variables are exposed in the Docker container

| Environment Variable    | Default Value      | Terraform Variable                                   |
|-------------------------|--------------------|------------------------------------------------------|
| `CAP_REGION`            | `null`             | `repository_settings.region`                         |
| `CAP_ACCOUNT_ID`        | `null`             | `repository_settings.account_id`                     |
| `CAP_AUTH_SECRET`       | `""`               | `authentication.username && authentication.password` |
| `CAP_ALLOW_ANONYMOUS`   | `null`             | `authentication.allow_anonymous`                     |
| `CAP_PORT`              | `5000`             | `networking.container_port`                          |
| `CAP_HEALTH_CHECK_PATH` | `/health`          | `var.networking.health_check.path`                   |
| `CAP_CONFIG_PATH`       | `/app/config.json` | `null`                                               |
| `CAP_REFRESH_CADENCE`   | `10800`            | `null`                                               |

### Examples

```terraform
# Example minimal usage
module "codeartifact-proxy" {
  repositories = [{
    domain = aws_codeartifact_domain.pypi.domain
    repository = aws_codeartifact_repository.pypi.repository
    hostname = "pypi.company.io"
    zone_name = "company.io"
    package_manager = "pypi"
  }]
  
  networking = {
    vpc_id = "VPC_ID"
    subnets = ["PRIVATE_SUBNET", "PRIVATE_SUBNET"]
  }

  authentication = {
    allow_anonymous = true
  }
}
```