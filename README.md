# Proyecto Terraform — Load Balancer con Tráfico Ponderado en GCP

**Curso:** Servicios en la Nube 2026-01
**Grupo:** 14
**Universidad Nacional de Colombia — Facultad de Minas**

## Descripción

Infraestructura como código (Terraform) que despliega en Google Cloud Platform un
HTTP Load Balancer global con dos backends completamente independientes:

- **Servicio Principal**: aplicación en producción.
- **Servicio de Contingencia**: página de mantenimiento.

El tráfico hacia ambos servicios se distribuye mediante pesos configurables en
`terraform.tfvars`, sin necesidad de modificar el código de la arquitectura
(`main.tf`) ni acceder a la consola web de GCP.

## Arquitectura

- **Red:** VPC dedicada (`vpc-proyecto-cloud`) con subred automática.
- **Cómputo:** 2 instancias `e2-micro` (Debian 12), cada una en su propia VM —
  aisladas entre sí para garantizar resiliencia ante fallos.
- **Balanceo:** HTTP(S) Load Balancer global (`EXTERNAL_MANAGED`) con
  `weighted_backend_services` en el `url_map`, que permite repartir tráfico por
  peso entre los dos backends desde una única IP pública.
- **Firewall:** reglas para HTTP (80, incluyendo rangos de Google para health
  checks) y SSH (22, solo para diagnóstico).

## Variables de control de tráfico

Editando únicamente `terraform.tfvars` y ejecutando `terraform apply`, se puede
activar cualquiera de los 3 escenarios de evaluación:

| Escenario | `peso_principal` | `peso_contingencia` | Resultado esperado |
|---|---|---|---|
| 1 — Producción Activa | `1000` | `0` | 100% de las visitas ven el Servicio Principal |
| 2 — Mantenimiento Total | `0` | `1000` | 100% de las visitas ven la Página de Error |
| 3 — Balance Equitativo | `500` | `500` | Las visitas alternan entre ambos servicios |

Ejemplo de `terraform.tfvars` para el Escenario 1 (configuración por defecto del repo):

```hcl
project_id        = "TU-PROJECT-ID"
region            = "us-central1"
zone              = "us-central1-a"
peso_principal    = 1000
peso_contingencia = 0
```

## Cómo desplegar

Requisitos: cuenta de GCP con créditos activos, Terraform >= 1.5, y autenticación
configurada (`gcloud auth application-default login`).

```bash
terraform init
terraform fmt
terraform plan
terraform apply
```

La IP pública del Load Balancer aparece en el output `ip_publica_load_balancer`
al finalizar el `apply`. Puede tardar entre 1 y 2 minutos en propagar
completamente (instalación de Apache + primer ciclo de health check).

> **Nota:** tras cualquier cambio de variables, esperar ~20-30
> segundos antes de probar en el navegador para que el `url_map` propague el
> cambio de pesos.

## Cómo destruir el entorno

```bash
terraform destroy
```

Es obligatorio ejecutar este comando al finalizar las pruebas para no consumir
créditos innecesariamente.

## Evidencias

Las capturas de pantalla de los 3 escenarios y del `terraform destroy` final se
encuentran en la carpeta [`evidencias/`](./evidencias).

## Acceso para revisión

El proyecto está configurado en GCP con el correo del profesor
(`vdrestrepot@unal.edu.co`) como **Editor** del proyecto, según lo solicitado en
el enunciado. El `project_id` está parametrizado en `terraform.tfvars`, por lo
que el repositorio puede ejecutarse en el proyecto sin modificar archivos `.tf`.