variable "name" {
}

variable "environment" {
}

variable "account_id" {
}

variable "logs_expiration_enabled" {
  default = false
}

variable "logs_expiration_days" {
  default = 30
}


data "aws_elb_service_account" "elb_account" {}

data "aws_iam_policy_document" "s3_policy" {
  statement {
    actions   = [
      "s3:PutObject"
    ]
    resources = [
      "arn:aws:s3:::${var.name}-${var.environment}-logs/*"
    ]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:root"]
    }
  }
  statement {
    actions   = [
      "s3:PutObject"
    ]
    resources = [
      "arn:aws:s3:::${var.name}-${var.environment}-logs/*"
    ]
    principals {
      type        = "AWS"
      identifiers = ["${data.aws_elb_service_account.elb_account.arn}"]
    }
  }
}


resource "aws_s3_bucket" "logs" {
  bucket = "${var.name}-${var.environment}-logs"

  acl = "log-delivery-write"

  lifecycle_rule {
    id = "logs-expiration"
    prefix = ""
    enabled = "${var.logs_expiration_enabled}"

    expiration {
      days = "${var.logs_expiration_days}"
    }
  }

  tags {
    Name        = "${var.name}-${var.environment}-logs"
    Environment = "${var.environment}"
  }

  policy = "${data.aws_iam_policy_document.s3_policy.json}"
}

output "id" {
  value = "${aws_s3_bucket.logs.id}"
}
