provider "azurerm" {
  features {}
}

data azurerm_subscription "primary" {}

data azurerm_image "this" {
  name_regex          = "^vault-1.4.0"
  resource_group_name = "packerdependencies"
  sort_descending = true
}

locals {
  permitted_ips = ["203.206.6.67","120.158.233.91"]
}

resource azurerm_resource_group "this" {
  name     = var.deployment_name
  location = var.location
}

resource azurerm_virtual_network "this" {
  name                = var.deployment_name
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
}

resource azurerm_subnet "this" {
  name                 = var.deployment_name
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefix       = "10.0.2.0/24"
}

resource azurerm_network_interface "this" {
  count               = var.cluster_size
  name                = "${var.deployment_name}-${count.index}-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = var.deployment_name
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.machines[count.index].id
  }
}

resource azurerm_linux_virtual_machine "this" {
  count               = var.cluster_size
  name                = "${var.deployment_name}-${count.index}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  size                = var.server_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.this[count.index].id,
  ]
  custom_data = base64encode(data.template_file.userdata[count.index].rendered)

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_id = data.azurerm_image.this.id

  identity {
    type = "SystemAssigned"
  }
}

resource azurerm_public_ip "this" {
  name                = var.deployment_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource azurerm_public_ip "machines" {
  count               = var.cluster_size
  name                = "${var.deployment_name}-${count.index}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"
  allocation_method   = "Static"
}


resource azurerm_lb "this" {
  name                = var.deployment_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = var.deployment_name
    public_ip_address_id = azurerm_public_ip.this.id
  }
}

resource azurerm_lb_rule "this" {
  resource_group_name            = azurerm_resource_group.this.name
  loadbalancer_id                = azurerm_lb.this.id
  name                           = "LBRule"
  protocol                       = "Tcp"
  frontend_port                  = 8200
  backend_port                   = 8200
  frontend_ip_configuration_name = var.deployment_name
  backend_address_pool_id = azurerm_lb_backend_address_pool.this.id
}

resource azurerm_lb_backend_address_pool "this" {
  resource_group_name = azurerm_resource_group.this.name
  loadbalancer_id     = azurerm_lb.this.id
  name                = var.deployment_name
}

resource azurerm_network_interface_backend_address_pool_association "this" {
  count                   = var.cluster_size
  network_interface_id    = azurerm_network_interface.this[count.index].id
  ip_configuration_name   = var.deployment_name
  backend_address_pool_id = azurerm_lb_backend_address_pool.this.id
}



resource azurerm_network_security_group "this" {
  name                = var.deployment_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    name                       = "test123"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes      = formatlist("%s/32", local.permitted_ips)
    destination_address_prefixes = azurerm_linux_virtual_machine.this.*.private_ip_address
  }

  security_rule {
    name                       = "vault"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8200"
    source_address_prefixes    = ["*"]
    destination_address_prefixes = azurerm_linux_virtual_machine.this.*.private_ip_address
  }
}

resource azurerm_network_interface_security_group_association "this" {
  count = var.cluster_size
  network_interface_id      = azurerm_network_interface.this[count.index].id
  network_security_group_id = azurerm_network_security_group.this.id
}


resource azurerm_role_definition "this" {
  name               = var.deployment_name
  scope              = data.azurerm_subscription.primary.id

  permissions {
    actions     = [
      "Microsoft.Compute/virtualMachineScaleSets/*/read",
      "Microsoft.Compute/virtualMachines/*/read"
    ]
    not_actions = []
  }

  assignable_scopes = [
    data.azurerm_subscription.primary.id,
  ]
}

resource azurerm_role_assignment "this" {
  count              = var.cluster_size
  scope              = data.azurerm_subscription.primary.id
  role_definition_id = azurerm_role_definition.this.id
  principal_id       = azurerm_linux_virtual_machine.this[count.index].identity[0].principal_id
}

data aws_route53_zone "this" {
  name         = "go.hashidemos.io"
  private_zone = false
}

resource aws_route53_record "this" {
  zone_id = data.aws_route53_zone.this.id
  name    = "azure-vault.${data.aws_route53_zone.this.name}"
  type    = "A"
  ttl     = "300"
  records = [azurerm_public_ip.this.ip_address]
}