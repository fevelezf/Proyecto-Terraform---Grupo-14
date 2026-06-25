# AGENTS.md — Guía para asistentes de IA

Este documento explica cómo leer, entender y operar este repositorio de
Terraform. Está dirigido a un LLM (o humano asistido por uno) que necesite
auditar, desplegar, o modificar el proyecto sin contexto previo.

## Resumen del proyecto en una línea

Terraform que despliega en GCP un HTTP Load Balancer global cuyo `url_map`
distribuye tráfico por **peso** (no por path ni dominio) entre dos backends
en VMs aisladas, controlado enteramente por dos variables numéricas.

## Estructura de archivos

| Archivo | Contenido |
|---|---|
| `main.tf` | Toda la infraestructura: red, firewall, instancias, health check, instance groups, backend services, url map, proxy, IP pública, forwarding rule |
| `variables.tf` | Declaración de variables (`project_id`, `region`, `zone`, `peso_principal`, `peso_contingencia`) |
| `terraform.tfvars` | Valores actuales de las variables — **este es el único archivo que cambia entre escenarios de evaluación** |
| `outputs.tf` | Expone la IP pública del LB y los pesos actuales tras `apply` |

## El mecanismo central (lo más importante de entender)

El control de tráfico por porcentaje vive en `google_compute_url_map.url_map_principal`,
específicamente en el bloque `default_route_action > weighted_backend_services`.
Cada `weighted_backend_services` referencia un backend service y un peso
(`var.peso_principal` o `var.peso_contingencia`, rango 0-1000). GCP normaliza
estos pesos de forma relativa: 1000-0 = 100%/0%, 500-500 = 50%/50%, etc.

**Restricción técnica importante:** este mecanismo de enrutamiento avanzado
(`weighted_backend_services`) solo es válido cuando `load_balancing_scheme =
"EXTERNAL_MANAGED"` en los `backend_service` y en el `forwarding_rule`. El
esquema clásico (`EXTERNAL`) no soporta reglas de enrutamiento avanzadas y
falla con error 400 si se intenta.

## Cómo simular los 3 escenarios de evaluación

Modificar únicamente `terraform.tfvars`:

```hcl
# Escenario 1 — Producción Activa
peso_principal    = 1000
peso_contingencia = 0

# Escenario 2 — Mantenimiento Total
peso_principal    = 0
peso_contingencia = 1000

# Escenario 3 — Balance Equitativo
peso_principal    = 500
peso_contingencia = 500
```

Después de cada cambio: `terraform apply` (solo modifica el `url_map`, no
recrea instancias) y esperar ~20-30 segundos de propagación antes de probar
la IP pública en el navegador.

## Comandos de despliegue estándar

```bash
terraform init      # primera vez o tras clonar el repo
terraform fmt        # formatear código
terraform plan        # revisar cambios antes de aplicar
terraform apply        # desplegar (pide confirmación "yes")
terraform destroy        # destruir todo al finalizar pruebas
```

## Verificación de salud (diagnóstico)

```bash
gcloud compute backend-services get-health backend-principal --global
gcloud compute backend-services get-health backend-contingencia --global
```

Debe mostrar `healthState: HEALTHY` para que el Load Balancer enrute tráfico
correctamente a esa instancia.

## Particularidades conocidas de este entorno (para evitar falsos diagnósticos)

1. **Tras recrear una instancia** (por ejemplo al cambiar `metadata_startup_script`),
   el `google_compute_instance_group` correspondiente puede no re-vincularse
   automáticamente en el mismo `apply`. Si `get-health` no devuelve
   `healthState`, correr `terraform apply` una segunda vez suele resolverlo
   (actualiza el campo `instances` del instance group).
2. Los scripts de arranque (`metadata_startup_script`) usan `replace(..., "\r\n", "\n")`
   para forzar saltos de línea Unix, evitando que un guardado con CRLF
   (común en editores de Windows) rompa el shebang `#!/bin/bash` y cause
   `exit status 127`.
3. El HTML servido incluye `<meta charset='UTF-8'>` explícito para que los
   acentos en español se rendericen correctamente en el navegador.

## Variable obligatoria para desplegar en otro proyecto GCP

`project_id` en `terraform.tfvars` debe apuntar al proyecto GCP destino. No se
requiere modificar ningún archivo `.tf` para cambiar de proyecto.

## Acceso IAM esperado

El correo `vdrestrepot@unal.edu.co` debe tener rol `roles/editor` en el
proyecto GCP de destino para poder ejecutar `terraform apply`/`destroy` desde
este repositorio sin modificaciones.