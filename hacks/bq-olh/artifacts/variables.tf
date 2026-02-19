## --------------------------------------------------------------
## Mandatory variable definitions
## --------------------------------------------------------------

variable "gcp_project_id" {
  type        = string
  description = "The GCP project ID to create resources in."
}

# Default value passed in
variable "gcp_region" {
  type        = string
  description = "Region to create resources in."
  default     = "us-central1"
}

# Default value passed in
variable "gcp_zone" {
  type        = string
  description = "Zone to create resources in."
  default     = "us-central1-c"
}

## --------------------------------------------------------------
variable "gcp_user" {
  type        = string
  description = "Email address of the lab user."
}

