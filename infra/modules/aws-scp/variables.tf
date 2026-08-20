variable "name" {
  type        = string
  description = "The name of the AWS SCP to create."
}

variable "description" {
  type        = string
  description = "The description of the AWS SCP to create."
}

variable "policy_content" {
  type        = string
  description = "The JSON policy document for the AWS SCP."
}

variable "target_ids" {
  type        = list(string)
  description = "A list of target IDs (OU or account) to attach the SCP to."
}