variable "name_prefix" {
  description = "Name prefix"
  type        = string
  default     = "ai-platform"
}

variable "container_repositories" {
  description = "List of container repository names"
  type        = list(string)
  default     = ["vllm", "kserve", "chat-demo", "rag-service"]
}

variable "model_repositories" {
  description = "List of model repository names"
  type        = list(string)
  default     = ["gemma-2b", "llama-3.1-8b"]
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
}
