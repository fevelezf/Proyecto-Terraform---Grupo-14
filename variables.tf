variable "project_id" {
  description = "ID del proyecto en GCP"
  type        = string
}

variable "region" {
  description = "Región de GCP"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zona de GCP"
  type        = string
  default     = "us-central1-a"
}

variable "peso_principal" {
  description = "Peso de tráfico hacia el Servicio Principal (0-1000)"
  type        = number
  default     = 800
}

variable "peso_contingencia" {
  description = "Peso de tráfico hacia el Servicio de Contingencia (0-1000)"
  type        = number
  default     = 200
}
