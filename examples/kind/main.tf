module "kind" {
  source = "git::https://github.com/GersonRS/modern-gitops-stack-module-cluster-kind.git?ref=v1.1.1"

  cluster_name       = local.cluster_name
  kubernetes_version = local.kubernetes_version
}

module "metallb" {
  source = "git::https://github.com/GersonRS/modern-gitops-stack-module-metallb.git?ref=v1.1.0"

  subnet = module.kind.kind_subnet
}

module "argocd_bootstrap" {
  source = "git::https://github.com/GersonRS/modern-gitops-stack-module-argocd.git//bootstrap?ref=v2.3.0"

  argocd_projects = {
    "${local.cluster_name}" = {
      destination_cluster = "in-cluster"
    }
  }

  depends_on = [module.kind]
}

module "metrics-server" {
  source = "git::https://github.com/GersonRS/modern-gitops-stack-module-metrics-server.git?ref=v1.1.0"

  argocd_project = local.cluster_name

  app_autosync = local.app_autosync

  kubelet_insecure_tls = true

  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

module "traefik" {
  source = "git::https://github.com/GersonRS/modern-gitops-stack-module-traefik.git//kind?ref=v2.5.0"

  argocd_project = local.cluster_name

  app_autosync           = local.app_autosync
  enable_service_monitor = local.enable_service_monitor

  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

module "cert-manager" {
  source = "git::https://github.com/GersonRS/modern-gitops-stack-module-cert-manager.git//self-signed?ref=v2.5.0"

  argocd_project = local.cluster_name

  app_autosync           = local.app_autosync
  enable_service_monitor = local.enable_service_monitor

  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

module "keycloak" {
  source = "git::https://github.com/GersonRS/modern-gitops-stack-module-keycloak.git?ref=v2.4.0"

  cluster_name   = local.cluster_name
  base_domain    = local.base_domain
  subdomain      = local.subdomain
  cluster_issuer = local.cluster_issuer
  argocd_project = local.cluster_name

  app_autosync = local.app_autosync

  dependency_ids = {
    traefik      = module.traefik.id
    cert-manager = module.cert-manager.id
  }
}

module "oidc" {
  source = "git::https://github.com/GersonRS/modern-gitops-stack-module-keycloak.git//oidc_bootstrap?ref=v2.4.0"

  cluster_name   = local.cluster_name
  base_domain    = local.base_domain
  subdomain      = local.subdomain
  cluster_issuer = local.cluster_issuer

  dependency_ids = {
    keycloak = module.keycloak.id
  }
}

module "postgresql" {
  source         = "git::https://github.com/GersonRS/modern-gitops-stack-module-postgresql.git?ref=v2.8.0"
  cluster_name   = local.cluster_name
  base_domain    = local.base_domain
  subdomain      = local.subdomain
  cluster_issuer = local.cluster_issuer
  argocd_project = local.cluster_name

  app_autosync           = local.app_autosync
  enable_service_monitor = local.enable_service_monitor
  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

module "minio" {
  source = "git::https://github.com/GersonRS/modern-gitops-stack-module-minio.git?ref=v2.5.0"

  cluster_name   = local.cluster_name
  base_domain    = local.base_domain
  subdomain      = local.subdomain
  cluster_issuer = local.cluster_issuer
  argocd_project = local.cluster_name

  app_autosync           = local.app_autosync
  enable_service_monitor = local.enable_service_monitor

  config_minio = local.minio_config

  oidc = module.oidc.oidc

  dependency_ids = {
    traefik      = module.traefik.id
    cert-manager = module.cert-manager.id
    oidc         = module.oidc.id
  }
}

module "zookeeper" {
  source                 = "git::https://github.com/GersonRS/modern-gitops-stack-module-zookeeper.git?ref=v1.2.0"
  cluster_name           = local.cluster_name
  base_domain            = local.base_domain
  subdomain              = local.subdomain
  cluster_issuer         = local.cluster_issuer
  argocd_project         = local.cluster_name
  app_autosync           = local.app_autosync
  enable_service_monitor = local.enable_service_monitor
  dependency_ids = {
    argocd = module.argocd_bootstrap.id
  }
}

module "nifi" {
  source                 = "git::https://github.com/GersonRS/modern-gitops-stack-module-nifi.git?ref=v1.3.0"
  cluster_name           = local.cluster_name
  base_domain            = local.base_domain
  subdomain              = local.subdomain
  cluster_issuer         = local.cluster_issuer
  argocd_project         = local.cluster_name
  app_autosync           = local.app_autosync
  enable_service_monitor = local.enable_service_monitor
  oidc                   = module.oidc.oidc
  dependency_ids = {
    zookeeper = module.zookeeper.id
  }
}

module "loki-stack" {
  source = "git::https://github.com/GersonRS/modern-gitops-stack-module-loki-stack.git//kind?ref=v1.1.0"

  argocd_project = local.cluster_name

  app_autosync = local.app_autosync

  logs_storage = {
    bucket_name = local.minio_config.buckets.0.name
    endpoint    = module.minio.endpoint
    access_key  = local.minio_config.users.0.accessKey
    secret_key  = local.minio_config.users.0.secretKey
  }

  dependency_ids = {
    minio = module.minio.id
  }
}

module "thanos" {
  source = "git::https://github.com/GersonRS/modern-gitops-stack-module-thanos.git//kind?ref=v1.1.0"

  cluster_name   = local.cluster_name
  base_domain    = local.base_domain
  subdomain      = local.subdomain
  cluster_issuer = local.cluster_issuer
  argocd_project = local.cluster_name

  app_autosync = local.app_autosync

  metrics_storage = {
    bucket_name = local.minio_config.buckets.1.name
    endpoint    = module.minio.endpoint
    access_key  = local.minio_config.users.1.accessKey
    secret_key  = local.minio_config.users.1.secretKey
  }

  thanos = {
    oidc = module.oidc.oidc
  }

  dependency_ids = {
    argocd       = module.argocd_bootstrap.id
    traefik      = module.traefik.id
    cert-manager = module.cert-manager.id
    minio        = module.minio.id
    keycloak     = module.keycloak.id
    oidc         = module.oidc.id
  }
}

module "kube-prometheus-stack" {
  source = "git::https://github.com/GersonRS/modern-gitops-stack-module-kube-prometheus-stack.git//kind?ref=v1.2.0"

  cluster_name   = local.cluster_name
  base_domain    = local.base_domain
  subdomain      = local.subdomain
  cluster_issuer = local.cluster_issuer
  argocd_project = local.cluster_name

  app_autosync = local.app_autosync

  metrics_storage = {
    bucket_name = local.minio_config.buckets.1.name
    endpoint    = module.minio.endpoint
    access_key  = local.minio_config.users.1.accessKey
    secret_key  = local.minio_config.users.1.secretKey
  }

  prometheus = {
    oidc = module.oidc.oidc
  }
  alertmanager = {
    oidc = module.oidc.oidc
  }
  grafana = {
    oidc = module.oidc.oidc
  }

  dependency_ids = {
    traefik      = module.traefik.id
    cert-manager = module.cert-manager.id
    minio        = module.minio.id
    oidc         = module.oidc.id
  }
}

module "airflow" {
  source         = "git::https://github.com/GersonRS/modern-gitops-stack-module-airflow.git?ref=v1.3.0"
  cluster_name   = local.cluster_name
  base_domain    = local.base_domain
  subdomain      = local.subdomain
  cluster_issuer = local.cluster_issuer
  argocd_project = local.cluster_name
  app_autosync   = local.app_autosync
  oidc           = module.oidc.oidc
  fernetKey      = base64encode(resource.random_password.airflow_fernetKey.result)
  storage = {
    bucket_name       = "airflow"
    endpoint          = module.minio.endpoint
    access_key        = module.minio.minio_root_user_credentials.username
    secret_access_key = module.minio.minio_root_user_credentials.password
  }
  database = {
    database = "airflow"
    user     = module.postgresql.credentials.user
    password = module.postgresql.credentials.password
    endpoint = module.postgresql.cluster_dns
  }
  # mlflow = {
  #   endpoint = module.mlflow.cluster_dns
  # }
  # ray = {
  #   endpoint = module.ray.cluster_dns
  # }
  dependency_ids = {
    argocd     = module.argocd_bootstrap.id
    traefik    = module.traefik.id
    oidc       = module.oidc.id
    minio      = module.minio.id
    postgresql = module.postgresql.id
  }
}

module "argocd" {
  source = "git::https://github.com/GersonRS/modern-gitops-stack-module-argocd.git?ref=v2.6.1"

  base_domain              = local.base_domain
  cluster_name             = local.cluster_name
  subdomain                = local.subdomain
  cluster_issuer           = local.cluster_issuer
  server_secretkey         = module.argocd_bootstrap.argocd_server_secretkey
  accounts_pipeline_tokens = module.argocd_bootstrap.argocd_accounts_pipeline_tokens
  argocd_project           = local.cluster_name

  app_autosync = local.app_autosync

  admin_enabled = false
  exec_enabled  = true

  oidc = {
    name         = "OIDC"
    issuer       = module.oidc.oidc.issuer_url
    clientID     = module.oidc.oidc.client_id
    clientSecret = module.oidc.oidc.client_secret
    requestedIDTokenClaims = {
      groups = {
        essential = true
      }
    }
  }

  rbac = {
    policy_csv = <<-EOT
      g, pipeline, role:admin
      g, modern-gitops-stack-admins, role:admin
    EOT
  }

  dependency_ids = {
    traefik               = module.traefik.id
    cert-manager          = module.cert-manager.id
    oidc                  = module.oidc.id
    kube-prometheus-stack = module.kube-prometheus-stack.id
  }
}
