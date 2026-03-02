variable "project_name" {
  type = string
}

variable "instance_count" {
  type    = number
  default = 3
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "iam_instance_profile" {
  type = string
}

variable "alb_dns" {
  type = string
}

variable "mockpg_ip" {
  type = string
}

variable "s3_bucket" {
  type = string
}

variable "stock" {
  type    = number
  default = 100
}
