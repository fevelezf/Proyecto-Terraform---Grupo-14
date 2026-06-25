output "ip_publica_load_balancer" {
  description = "IP pública única para acceder al servicio"
  value       = google_compute_global_address.ip_publica.address
}

output "peso_actual_principal" {
  description = "Peso configurado actualmente para el Servicio Principal"
  value       = var.peso_principal
}

output "peso_actual_contingencia" {
  description = "Peso configurado actualmente para el Servicio de Contingencia"
  value       = var.peso_contingencia
}