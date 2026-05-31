variable "system_instance_types" {
  description = "Instance types for system node group"
  type        = list(string)
  default     = ["t3.medium", "t3.large"]
}

variable "system_min_size" {
  description = "Minimum size for system node group"
  type        = number
  default     = 1
}

variable "system_max_size" {
  description = "Maximum size for system node group"
  type        = number
  default     = 5
}

variable "system_labels" {
  description = "Additional labels for system node group"
  type        = map(string)
  default     = {}
}

variable "gpu_node_groups" {
  description = "GPU node group configurations"
  type = map(object({
    instance_types = list(string)
    disk_size      = optional(number, 100)
    min_size       = number
    max_size       = number
    spot           = optional(bool, false)
    accelerator    = string
    labels         = optional(map(string), {})
  }))
  default = {}
}
