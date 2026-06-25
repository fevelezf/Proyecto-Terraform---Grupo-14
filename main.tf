# Definimos el provider de Google y la versión mínima requerida.
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# Configuramos el provider de Google con el ID del proyecto y la región.
provider "google" {
  project = var.project_id
  region  = var.region
}

# Creamos una VPC propia (No usamos la deafult) para tener control total sobre las reglas del firewall.
resource "google_compute_network" "vpc_red" {
  name                    = "vpc-proyecto-cloud"
  auto_create_subnetworks = true
}

#Permimos tradico HTTP en el puerto 80, incluyendo los rangos de IP que google usa para sus health checks.
resource "google_compute_firewall" "permitir_http" {
  name    = "permitir-http-health-check"
  network = google_compute_network.vpc_red.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16", "0.0.0.0/0"]
}

#Permimos tráfico SSH en el puerto 22 porque la VPC propia no traerá reglas por defecto y necesitamos poder conectarnos a las instancias.
resource "google_compute_firewall" "permitir_ssh" {
  name    = "permitir-ssh"
  network = google_compute_network.vpc_red.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Instancia del svc principal. El startup script instala apache y pone el HTML de producción.
resource "google_compute_instance" "servicio_principal" {
  name         = "servicio-principal"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = google_compute_network.vpc_red.name
    access_config {} 
  }

  metadata_startup_script = replace(<<-EOF
        #!/bin/bash
        apt-get update
        apt-get install -y apache2
        echo "<html><head><meta charset='UTF-8'></head><body><h1>Bienvenido al Servicio Principal - Versión Producción</h1></body></html>" > /var/www/html/index.html
        systemctl restart apache2
    EOF
  , "\r\n", "\n")

  tags = ["servicio-principal"]
}

# Instancia de svc de contingencia. Va en una VM aparte para prevenir los fallos.
resource "google_compute_instance" "servicio_contingencia" {
  name         = "servicio-contingencia"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = google_compute_network.vpc_red.name
    access_config {}
  }

  metadata_startup_script = replace(<<-EOF
        #!/bin/bash
        apt-get update
        apt-get install -y apache2
        echo "<html><head><meta charset='UTF-8'></head><body><h1>Error 503 - Sitio en Mantenimiento Programado</h1></body></html>" > /var/www/html/index.html
        systemctl restart apache2
    EOF
  , "\r\n", "\n")

  tags = ["servicio-contingencia"]
}

//LOAD BALANCER HEALTH CHECK
# El Load Balancer necesita saber si cada instancia está viva antes de mandarle tráfico.
resource "google_compute_health_check" "health_check" {
  name               = "health-check-http"
  timeout_sec        = 5
  check_interval_sec = 10

  http_health_check {
    port = 80
  }
}

//LOAD BALANCER INSTANCE GROUPS
# Agrupamos la instancia principal en un Instance Group porque el backend service no apunta a VMs directamente.
resource "google_compute_instance_group" "grupo_principal" {
  name      = "grupo-servicio-principal"
  zone      = var.zone
  instances = [google_compute_instance.servicio_principal.self_link]

  named_port {
    name = "http"
    port = 80
  }
}

# Lo mismo para la instancia de contingencia.
resource "google_compute_instance_group" "grupo_contingencia" {
  name      = "grupo-servicio-contingencia"
  zone      = var.zone
  instances = [google_compute_instance.servicio_contingencia.self_link]

  named_port {
    name = "http"
    port = 80
  }
}

//LOAD BALANCER BACKEND SERVICES
# Backend service del servicio principal. Usamos EXTERNAL_MANAGED porque es el único esquema que admite
# reglas de enrutamiento avanzado (weighted_backend_services) en el url_map.
resource "google_compute_backend_service" "backend_principal" {
  name                  = "backend-principal"
  protocol              = "HTTP"
  health_checks         = [google_compute_health_check.health_check.id]
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_instance_group.grupo_principal.self_link
  }
}

# Lo mismo para el backend de contingencia.
resource "google_compute_backend_service" "backend_contingencia" {
  name                  = "backend-contingencia"
  protocol              = "HTTP"
  health_checks         = [google_compute_health_check.health_check.id]
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_instance_group.grupo_contingencia.self_link
  }
}

//LOAD BALANCER URL MAP
# Repartimos el tráfico por peso entre los dos backends.
# Los pesos vienen de  terraform.tfvars basta cambiarlo alli  para cambiar el comportamiento.
resource "google_compute_url_map" "url_map_principal" {
  name = "url-map-trafico"

  default_route_action {
    weighted_backend_services {
      backend_service = google_compute_backend_service.backend_principal.self_link
      weight          = var.peso_principal
    }

    weighted_backend_services {
      backend_service = google_compute_backend_service.backend_contingencia.self_link
      weight          = var.peso_contingencia
    }
  }
}
# El proxy HTTP conecta el forwarding rule con mi url_map (donde están los pesos).
resource "google_compute_target_http_proxy" "proxy_http" {
  name    = "proxy-http-proyecto"
  url_map = google_compute_url_map.url_map_principal.self_link
}

# Reservo una única IP pública global — este es el "Punto de Entrada Único" que pide el enunciado.
resource "google_compute_global_address" "ip_publica" {
  name = "ip-publica-proyecto"
}

# El forwarding rule conecta mi IP pública con el proxy. Debe usar EXTERNAL_MANAGED, igual que los backends.
resource "google_compute_global_forwarding_rule" "regla_forwarding" {
  name                  = "forwarding-rule-http"
  target                = google_compute_target_http_proxy.proxy_http.self_link
  port_range            = "80"
  ip_address            = google_compute_global_address.ip_publica.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}





