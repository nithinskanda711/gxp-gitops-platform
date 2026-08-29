variable "region" {
  description = "AWS region. Keep this consistent with wherever you run workloads."
  type        = string
  default     = "eu-west-1"
}

variable "project" {
  description = "Short name used to prefix the repository"
  type        = string
  default     = "gxp"
}

variable "owner" {
  description = "Tag applied to every resource so nothing is orphaned anonymously"
  type        = string
}

variable "retain_image_count" {
  description = "How many images to keep before the lifecycle policy expires the oldest"
  type        = number
  default     = 20
}
