terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "vpc_red" {
  name                    = "vpc-proyecto-cloud"
  auto_create_subnetworks = true
}

resource "google_compute_firewall" "permitir_http" {
  name    = "permitir-http-health-check"
  network = google_compute_network.vpc_red.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16", "0.0.0.0/0"]
}

resource "google_compute_firewall" "permitir_ssh" {
  name    = "permitir-ssh"
  network = google_compute_network.vpc_red.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}


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
resource "google_compute_health_check" "health_check" {
  name               = "health-check-http"
  timeout_sec        = 5
  check_interval_sec = 10

  http_health_check {
    port = 80
  }
}

//LOAD BALANCER INSTANCE GROUPS
resource "google_compute_instance_group" "grupo_principal" {
  name      = "grupo-servicio-principal"
  zone      = var.zone
  instances = [google_compute_instance.servicio_principal.self_link]

  named_port {
    name = "http"
    port = 80
  }
}

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
resource "google_compute_backend_service" "backend_principal" {
  name                  = "backend-principal"
  protocol              = "HTTP"
  health_checks         = [google_compute_health_check.health_check.id]
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group = google_compute_instance_group.grupo_principal.self_link
  }
}

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

resource "google_compute_target_http_proxy" "proxy_http" {
  name    = "proxy-http-proyecto"
  url_map = google_compute_url_map.url_map_principal.self_link
}

resource "google_compute_global_address" "ip_publica" {
  name = "ip-publica-proyecto"
}

resource "google_compute_global_forwarding_rule" "regla_forwarding" {
  name                  = "forwarding-rule-http"
  target                = google_compute_target_http_proxy.proxy_http.self_link
  port_range            = "80"
  ip_address            = google_compute_global_address.ip_publica.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}





