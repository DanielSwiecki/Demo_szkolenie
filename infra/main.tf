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

  ports {
    internal = 3000
    external = 3001
  }

  networks_advanced {
    name = docker_network.green_net.name
  }

  must_run = true
  restart  = "no"
}
