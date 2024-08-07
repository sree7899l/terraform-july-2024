resource "azurerm_resource_group" "tektutor_resource_group" {
  name = var.resource_group_name 
  location = var.location 
}

resource "azurerm_virtual_network" "my_virtual_network" {
  name = "my-virtual-network"
  location = azurerm_resource_group.tektutor_resource_group.location
  resource_group_name = azurerm_resource_group.tektutor_resource_group.name

  address_space = ["10.20.0.0/16"]
  depends_on = [
     azurerm_resource_group.tektutor_resource_group
  ]
}

resource "azurerm_subnet" "my_subnet" {
   name = "my-subnet"
   resource_group_name = azurerm_resource_group.tektutor_resource_group.name
  
   virtual_network_name = azurerm_virtual_network.my_virtual_network.name
   address_prefixes = [ "10.20.1.0/24" ]
   depends_on = [
      azurerm_virtual_network.my_virtual_network
   ]
}

resource "azurerm_public_ip" "my_vm_public_ip" {
  count = var.vm_count
  name = "my-vm-public-ip-${count.index}"

  resource_group_name = azurerm_resource_group.tektutor_resource_group.name
  location = azurerm_resource_group.tektutor_resource_group.location

  allocation_method = "Dynamic"
  depends_on = [
	azurerm_resource_group.tektutor_resource_group
  ]
}

resource "azurerm_network_interface" "my_network_card" {
   count = var.vm_count
   name = "my-network-card-${count.index}"
   resource_group_name = azurerm_resource_group.tektutor_resource_group.name
   location = azurerm_resource_group.tektutor_resource_group.location

   ip_configuration {
           name = "internal"
	   subnet_id = azurerm_subnet.my_subnet.id
	   private_ip_address_allocation = "Dynamic"
	   public_ip_address_id = azurerm_public_ip.my_vm_public_ip[count.index].id
   }

   depends_on = [
     azurerm_subnet.my_subnet
   ]
}

resource "azurerm_network_security_group" "firewall" {
	count = var.vm_count
	
	name = "firewall-${count.index}"

	resource_group_name = azurerm_resource_group.tektutor_resource_group.name
	location = azurerm_resource_group.tektutor_resource_group.location

	security_rule {
	  name 				= "AllowSSH"
	  priority			= 300
	  direction			= "Inbound"
	  access			= "Allow"
	  protocol			= "Tcp"
	  source_port_range		= "*"
	  source_address_prefix 	= "*"
	  destination_port_range	= "22"
	  destination_address_prefix	= "*"
	}
	security_rule {
	  name 				= "AllowICMP"
	  priority			= 310
	  direction			= "Inbound"
	  access			= "Allow"
	  protocol			= "Icmp"
	  source_port_range		= "*"
	  source_address_prefix 	= "*"
	  destination_port_range	= "*"
	  destination_address_prefix	= "*"
	}
	security_rule {
	  name 				= "AllowHttp"
	  priority			= 320
	  direction			= "Inbound"
	  access			= "Allow"
	  protocol			= "Tcp"
	  source_port_range		= "*"
	  source_address_prefix 	= "*"
	  destination_port_range	= "80"
	  destination_address_prefix	= "*"
	}

	depends_on = [
		azurerm_resource_group.tektutor_resource_group
	]
}

resource "azurerm_network_interface_security_group_association" "apply_firewall_rules_on_network_card" {
	count = var.vm_count
	network_interface_id = azurerm_network_interface.my_network_card[count.index].id
	network_security_group_id = azurerm_network_security_group.firewall[count.index].id

	depends_on = [
		azurerm_network_interface.my_network_card,
		azurerm_network_security_group.firewall
	]
}

resource "tls_private_key" "my_key_pair" {
  	algorithm = "RSA"
	rsa_bits  = 4096
}

resource "azurerm_linux_virtual_machine" "my_linux_vm" {
	count = var.vm_count

	name = "my-linux-vm-${count.index}"

	resource_group_name = azurerm_resource_group.tektutor_resource_group.name
	location = azurerm_resource_group.tektutor_resource_group.location

	size = "Standard_F2"
	admin_username = "azureuser"
	disable_password_authentication = true

	network_interface_ids = [
		azurerm_network_interface.my_network_card[count.index].id
	]

	admin_ssh_key {
		username = "azureuser"
		public_key = tls_private_key.my_key_pair.public_key_openssh
	}

	os_disk {
		caching = "ReadWrite"
		storage_account_type = "Standard_LRS"
	}

	source_image_reference {
		publisher = "Canonical"	
    		offer = "0001-com-ubuntu-server-jammy"
    		sku = "22_04-lts"
		version = "latest"
	}
	depends_on = [
		azurerm_network_interface.my_network_card,
		tls_private_key.my_key_pair
	]
}

resource "local_file" "private_key_file" {
	content = tls_private_key.my_key_pair.private_key_pem
	filename = "./key.pem"
}

resource "null_resource" "change_private_key_file_permission" {
	provisioner "local-exec" {
		command = "chmod 400 ./key.pem"
	}
	depends_on = [
		local_file.private_key_file
	]
}

resource "time_sleep" "wait_120_seconds" {
	depends_on = [ azurerm_linux_virtual_machine.my_linux_vm]

	create_duration = "120s"
}

resource "null_resource" "install_nginx_web_server_on_azure_vms" {
	depends_on = [time_sleep.wait_120_seconds]

	count = var.vm_count

	connection {
		type = "ssh"
		user = "azureuser"
		private_key = tls_private_key.my_key_pair.private_key_pem
		host = azurerm_linux_virtual_machine.my_linux_vm[count.index].public_ip_address
	}

	provisioner "remote-exec" {
		inline = [
			"sudo apt update",
			"sudo apt install -y nginx"
		]
	}
}

output "public_ip_address" {
	value = azurerm_linux_virtual_machine.my_linux_vm.*.public_ip_address
}

output "private_key" {
	value = tls_private_key.my_key_pair.private_key_pem
	sensitive = true
}
