variable "name" {
    type        = string
    description = "Name of the AWS account to create"
}

variable "email" {
    type        = string
    description = "Email address for the AWS account"
}
    
variable "parent_ou_id" {
    type        = string
    description = "ID of the parent organizational unit for the AWS account"
}