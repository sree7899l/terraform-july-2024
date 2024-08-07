resource "azurerm_resource_group" "teklabs" {
  name     = "tektutor-resources"
  location = "southindia"
}

resource "azurerm_container_group" "teklabs" {
  name                = "tektutorlabs"
  location            = azurerm_resource_group.teklabs.location
  resource_group_name = azurerm_resource_group.teklabs.name
  ip_address_type     = "Public"
  dns_name_label      = "tektutor-labs-dns"
  os_type             = "Linux"

  container {
    name   = "hello-world"
    image  = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
    cpu    = "0.5"
    memory = "1.5"

    ports {
      port     = 443
      protocol = "TCP"
    }
  }

  container {
    name   = "sidecar"
    image  = "mcr.microsoft.com/azuredocs/aci-tutorial-sidecar"
    cpu    = "0.5"
    memory = "1.5"
  }

  tags = {
    environment = "testing"
  }
}
