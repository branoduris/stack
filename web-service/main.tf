/**
 * The web-service is similar to the `service` module, but the
 * it provides a __public__ ELB instead.
 *
 * Usage:
 *
 *      module "auth_service" {
 *        source    = "github.com/segmentio/stack/service"
 *        name      = "auth-service"
 *        image     = "auth-service"
 *        cluster   = "default"
 *      }
 *
 */

/**
 * Required Variables.
 */

variable "vpc_id" {
  description = "VPC ID"
}

variable "environment" {
  description = "Environment tag, e.g prod"
}

variable "image" {
  description = "The docker image name, e.g nginx"
}

variable "name" {
  description = "The service name, if empty the service name is defaulted to the image name"
  default     = ""
}

variable "version" {
  description = "The docker image version"
  default     = "latest"
}

variable "subnet_ids" {
  description = "Comma separated list of subnet IDs that will be passed to the ELB module"
}

variable "security_groups" {
  description = "Comma separated list of security group IDs that will be passed to the ELB module"
}

variable "port" {
  description = "The container host port"
}

variable "cluster" {
  description = "The cluster name or ARN"
}

variable "log_bucket" {
  description = "The S3 bucket ID to use for the ELB"
}

variable "ssl_certificate_id" {
  description = "SSL Certificate ID to use"
}

variable "iam_role" {
  description = "IAM Role ARN to use"
}

variable "external_dns_name" {
  description = "The subdomain under which the ELB is exposed externally, defaults to the task name"
  default     = ""
}

variable "internal_dns_name" {
  description = "The subdomain under which the ELB is exposed internally, defaults to the task name"
  default     = ""
}

variable "external_zone_id" {
  description = "The zone ID to create the record in"
}

variable "internal_zone_id" {
  description = "The zone ID to create the record in"
}

/**
 * Options.
 */

variable "healthcheck" {
  description = "Path to a healthcheck endpoint"
  default     = "/"
}

variable "container_port" {
  description = "The container port"
  default     = 3000
}

variable "command" {
  description = "The raw json of the task command"
  default     = "[]"
}

variable "env_vars" {
  description = "The raw json of the task env vars"
  default     = "[]"
}

variable "desired_count" {
  description = "The desired count"
  default     = 2
}

variable "memory" {
  description = "The number of MiB of memory to reserve for the container"
  default     = 512
}

variable "cpu" {
  description = "The number of cpu units to reserve for the container"
  default     = 512
}

variable "deployment_minimum_healthy_percent" {
  description = "lower limit (% of desired_count) of # of running tasks during a deployment"
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "upper limit (% of desired_count) of # of running tasks during a deployment"
  default     = 200
}

provider "random" {
  version = "= 1.1.0"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}


/**
 * Resources.
 */

resource "aws_ecs_service" "main" {
  name                               = "${module.task.name}"
  cluster                            = "${var.cluster}"
  task_definition                    = "${module.task.arn}"
  desired_count                      = "${var.desired_count}"
  iam_role                           = "${var.iam_role}"
  deployment_minimum_healthy_percent = "${var.deployment_minimum_healthy_percent}"
  deployment_maximum_percent         = "${var.deployment_maximum_percent}"

  load_balancer {
    // elb_name       = "${module.elb.id}"
    target_group_arn = "${module.alb.target_group_arns[0]}"
    container_name = "${module.task.name}"
    container_port = "${var.container_port}"
  }

  lifecycle {
    create_before_destroy = true
  }

  // depends_on = ["module.alb.target_group_arns"]
}

module "task" {
  source = "../task"

  name          = "${coalesce(var.name, replace(var.image, "/", "-"))}"
  image         = "${var.image}"
  image_version = "${var.version}"
  command       = "${var.command}"
  env_vars      = "${var.env_vars}"
  memory        = "${var.memory}"
  cpu           = "${var.cpu}"

  ports = <<EOF
  [
    {
      "containerPort": ${var.container_port},
      "hostPort": ${var.port}
    }
  ]
EOF
}




module "alb" {
  source                        = "terraform-aws-modules/alb/aws"
  load_balancer_name            = "${module.task.name}-${random_string.suffix.result}"

  subnets                   = ["${split(",", var.subnet_ids)}"]
  security_groups           = ["${split(",",var.security_groups)}"]

  // log_enable                    = false
  log_bucket_name               = "${var.log_bucket}"
  // log_location_prefix           = "my-alb-logs"
  
  vpc_id                        = "${var.vpc_id}"
  // https_listeners               = "${list(map("certificate_arn", "arn:aws:iam::123456789012:server-certificate/test_cert-123456789012", "port", 443))}"
  // https_listeners_count         = "1"
  http_tcp_listeners            = "${list(map("port", "80", "protocol", "HTTP"))}"
  http_tcp_listeners_count      = "1"
  target_groups                 = "${list(map("name", "${module.task.name}-tg", "backend_protocol", "HTTP", "backend_port", "80"))}"
  target_groups_count           = "1"

  tags {
    Name        = "${module.task.name}"
    Environment = "${var.environment}"
  }
}

// module "elb" {
//   source = "./elb"

//   name               = "${module.task.name}"
//   port               = "${var.port}"
//   environment        = "${var.environment}"
//   subnet_ids         = "${var.subnet_ids}"
//   external_dns_name  = "${coalesce(var.external_dns_name, module.task.name)}"
//   internal_dns_name  = "${coalesce(var.internal_dns_name, module.task.name)}"
//   healthcheck        = "${var.healthcheck}"
//   external_zone_id   = "${var.external_zone_id}"
//   internal_zone_id   = "${var.internal_zone_id}"
//   security_groups    = "${var.security_groups}"
//   log_bucket         = "${var.log_bucket}"
//   ssl_certificate_id = "${var.ssl_certificate_id}"
// }


resource "aws_route53_record" "external" {
  zone_id = "${var.external_zone_id}"
  name    = "${var.external_dns_name}"
  type    = "A"

  alias {
    zone_id                = "${module.alb.load_balancer_zone_id}"
    name                   = "${module.alb.dns_name}"
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "internal" {
  zone_id = "${var.internal_zone_id}"
  name    = "${var.internal_dns_name}"
  type    = "A"

  alias {
    zone_id                = "${module.alb.load_balancer_zone_id}"
    name                   = "${module.alb.dns_name}"
    evaluate_target_health = false
  }
}

/**
 * Outputs.
 */

// The name of the ELB
output "name" {
  value = "${module.task.name}-${random_string.suffix.result}"
}

// The DNS name of the ELB
output "dns" {
  value = "${module.alb.dns_name}"
}

// The id of the ELB
output "elb" {
  value = "${module.alb.load_balancer_id}"
}

// The zone id of the ELB
output "zone_id" {
  value = "${module.alb.load_balancer_zone_id}"
}

// FQDN built using the zone domain and name (external)
output "external_fqdn" {
  value = "${aws_route53_record.external.fqdn}"
}

// FQDN built using the zone domain and name (internal)
output "internal_fqdn" {
  value = "${aws_route53_record.internal.fqdn}"
}
