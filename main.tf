provider "azurerm" {
  features {}
  subscription_id = "4461c28c-9e8b-494a-81f4-a4588f104448"
}

#Resource group
resource "azurerm_resource_group" "rg" {
  name     = "terraform-${var.env_name}-resource-group"
  location = "West Europe"
}

#Virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "terraform-${var.env_name}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

#Subnet 1
resource "azurerm_subnet" "subnet1" {
  name                 = "terraform-${var.env_name}-subnet1"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

#Subnet 2
resource "azurerm_subnet" "subnet2" {
  name                 = "terraform-${var.env_name}-subnet2"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

#Network security group
resource "azurerm_network_security_group" "nsg" {
  name                = "terraform-${var.env_name}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

#SSH connection
  dynamic "security_rule" {
    for_each = var.allowed_ips
    content {
      name                       = "SSH-${security_rule.value}"
      priority                   = 1001 + index(var.allowed_ips, security_rule.value)
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = security_rule.value
      destination_address_prefix = "*"
    }
  }

#WEB connection
  dynamic "security_rule" {
    for_each = var.allowed_ips
    content {
      name                       = "HTTP-${security_rule.value}"
      priority                   = 2001 + index(var.allowed_ips, security_rule.value)
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = security_rule.value
      destination_address_prefix = "*"
    }
  }
}

#Subnet 1 NCG association
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association1" {
  subnet_id                 = azurerm_subnet.subnet1.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

#Subnet 2 NCG association
resource "azurerm_subnet_network_security_group_association" "subnet_nsg_association2" {
  subnet_id                 = azurerm_subnet.subnet2.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

#Public IP
resource "azurerm_public_ip" "pip" {
  count               = 2
  name                = "terraform-${var.env_name}-pip-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

#Netowrk interface
resource "azurerm_network_interface" "nic" {
  count               = 2
  name                = "terraform-${var.env_name}-nic-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = count.index == 0 ? azurerm_subnet.subnet1.id : azurerm_subnet.subnet2.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip[count.index].id
  }
}

#Private key
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content  = tls_private_key.ssh_key.private_key_pem
  filename = "keyhw.pem"
}

#Create VM
resource "azurerm_linux_virtual_machine" "vm" {
  count                 = 2
  name                  = "terraform-${var.env_name}-vm-${count.index}"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = "Standard_B1s"
  admin_username        = "adminuser"
  disable_password_authentication = true
  network_interface_ids = [azurerm_network_interface.nic[count.index].id]
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.ssh_key.public_key_openssh
  }
}
