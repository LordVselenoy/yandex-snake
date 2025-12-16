terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

provider "yandex" {
  token     = "y0__xDB04yfBxjB3RMg5PfA1xWY7kh3Q6ATPCDhnsfe5S4DH7roMg" 
  cloud_id  = "b1go56q1stmpe0hret4l"
  folder_id = "b1glkhclsjbhunv6p1fr"
  zone      = "ru-central1-a"
}

# 1. Сеть
resource "yandex_vpc_network" "k8s-network" {
  name = "k8s-network"
}

# 2. Подсеть
resource "yandex_vpc_subnet" "k8s-subnet" {
  name           = "k8s-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.k8s-network.id
  v4_cidr_blocks = ["10.1.0.0/16"]
}

# 3. Сервисный аккаунт
resource "yandex_iam_service_account" "k8s-sa" {
  name = "k8s-robot"
}

# Права
resource "yandex_resourcemanager_folder_iam_member" "editor" {
  folder_id = "b1glkhclsjbhunv6p1fr"
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "images-puller" {
  folder_id = "b1glkhclsjbhunv6p1fr"
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.k8s-sa.id}"
}

# 4. Кластер Kubernetes
resource "yandex_kubernetes_cluster" "k8s-zonal" {
  name        = "snake-cluster"
  network_id  = yandex_vpc_network.k8s-network.id

  master {
    version = "1.27"
    zonal {
      zone      = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.k8s-subnet.id
    }
    public_ip = true
  }

  service_account_id      = yandex_iam_service_account.k8s-sa.id
  node_service_account_id = yandex_iam_service_account.k8s-sa.id

  depends_on = [
    yandex_resourcemanager_folder_iam_member.editor,
    yandex_resourcemanager_folder_iam_member.images-puller
  ]
}

# 5. Группа узлов
resource "yandex_kubernetes_node_group" "k8s-ng" {
  cluster_id  = yandex_kubernetes_cluster.k8s-zonal.id
  name        = "snake-nodes"
  version     = "1.27"

  instance_template {
    platform_id = "standard-v2"
    network_interface {
      nat                = true
      subnet_ids         = [yandex_vpc_subnet.k8s-subnet.id]
    }
    resources {
      memory = 2
      cores  = 2
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
    }
  }
}

# 6. Реестр
resource "yandex_container_registry" "my-reg" {
  name = "snake-registry"
}

output "cluster_id" {
  value = yandex_kubernetes_cluster.k8s-zonal.id
}

output "registry_id" {
  value = yandex_container_registry.my-reg.id
}