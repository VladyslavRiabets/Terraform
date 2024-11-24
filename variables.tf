variable "env_name" {
  description = "Environment name for resources"
  default     = "homework"
}

variable "allowed_ips" {
  description = "List of IPs allowed for SSH and HTTP access"
  type        = list(string)
  default     = ["178.54.56.54"]
}
