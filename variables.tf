variable "region" {
  description = "AWS region"
  type        = string
}

variable "s3_bucket_name" {
  description = "Nombre del bucket S3"
  type        = string
}

variable "db_identifier" {
  description = "Identificador de la base de datos"
  type        = string
}

variable "db_username" {
  description = "Usuario de la base de datos"
  type        = string
}

variable "db_password" {
  description = "Contraseña de la base de datos"
  type        = string
  sensitive   = true
}

variable "docdb_username" {
  description = "Usuario Nosql base de datos"
  type = string
}

variable "docdb_password" {
  description = "Contraseña de la Nosql base de datos"
  type        = string
  sensitive   = true
}