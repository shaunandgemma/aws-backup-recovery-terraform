variable "backup_alert_email" {
  description = "Email address that receives backup alerts."
  type        = string
  sensitive   = true
}

variable "restored_data_volume_id" {
  description = "Existing restored EBS volume to attach to the recovery server."
  type        = string

  validation {
    condition     = can(regex("^vol-([0-9a-f]{8}|[0-9a-f]{17})$", var.restored_data_volume_id))
    error_message = "Enter a valid EBS volume ID beginning with vol-."
  }
}

