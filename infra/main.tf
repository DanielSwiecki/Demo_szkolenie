terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

resource "docker_network" "green_net" {
  name = "green_net"
}

resource "docker_container" "app" {
  name  = "green-app-staging"
  image = "${var.image_name}:${var.tag}"

  # Wewnętrznie aplikacja słucha na 5000, na hoście otwieramy 3001 (opcjonalnie)
  ports {
    internal = 5000
    external = 3001
  }

  networks_advanced {
    name = docker_network.green_net.name
  }

  must_run = true
  restart  = "no"
}
