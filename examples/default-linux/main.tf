data "azurerm_client_config" "current" {}

# This ensures we have unique CAF compliant names for our resources.
module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.1"
}

module "regions" {
  source                    = "Azure/avm-utl-regions/azurerm"
  version                   = "=0.1.0"
  availability_zones_filter = true
}

resource "random_integer" "region_index" {
  max = length(module.regions.regions_by_name) - 1
  min = 0
}

resource "random_integer" "zone_index" {
  max = length(module.regions.regions_by_name[module.regions.regions[random_integer.region_index.result].name].zones)
  min = 1
}

module "get_valid_sku_for_deployment_region" {
  source = "../../modules/sku_selector"

  deployment_region = module.regions.regions[random_integer.region_index.result].name
}

# This is required for resource modules
resource "azurerm_resource_group" "this" {
  location = module.regions.regions[random_integer.region_index.result].name
  name     = module.naming.resource_group.name_unique
  tags     = local.tags
}

resource "azurerm_virtual_network" "this" {
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.this.location
  name                = module.naming.virtual_network.name_unique
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_subnet" "subnet" {
  address_prefixes     = ["10.0.1.0/24"]
  name                 = module.naming.subnet.name_unique
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
}

# network security group for the nic with a rule to allow http traffic
resource "azurerm_network_security_group" "nic" {
  location            = azurerm_resource_group.this.location
  name                = "${module.naming.network_security_group.name_unique}-nic"
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    access                     = "Allow"
    destination_address_prefix = "*"
    destination_port_range     = "80"
    direction                  = "Inbound"
    name                       = "allow-http"
    priority                   = 100
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    source_port_range          = "*"
  }
}

# network security group for the subnet with a rule to allow http traffic
resource "azurerm_network_security_group" "subnet" {
  location            = azurerm_resource_group.this.location
  name                = "${module.naming.network_security_group.name_unique}-subnet"
  resource_group_name = azurerm_resource_group.this.name

  security_rule {
    access                     = "Allow"
    destination_address_prefix = "*"
    destination_port_range     = "80"
    direction                  = "Inbound"
    name                       = "allow-http"
    priority                   = 100
    protocol                   = "Tcp"
    source_address_prefix      = "*"
    source_port_range          = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  network_security_group_id = azurerm_network_security_group.subnet.id
  subnet_id                 = azurerm_subnet.subnet.id
}

resource "azurerm_public_ip" "natgwpip" {
  allocation_method   = "Static"
  location            = azurerm_resource_group.this.location
  name                = module.naming.public_ip.name_unique
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"
  tags                = local.tags
  zones               = ["1", "2", "3"]
}

resource "azurerm_nat_gateway" "this" {
  location            = azurerm_resource_group.this.location
  name                = module.naming.nat_gateway.name_unique
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
  zones               = ["1"]
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.natgwpip.id
}

resource "azurerm_subnet_nat_gateway_association" "this" {
  nat_gateway_id = azurerm_nat_gateway.this.id
  subnet_id      = azurerm_subnet.subnet.id
}

resource "tls_private_key" "example_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# create key vault to store SSH private key, provide deployment user RBAC access to Secrets and Keys
module "avm_res_keyvault_vault" {
  source                      = "Azure/avm-res-keyvault-vault/azurerm"
  version                     = "=0.7.1"
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  name                        = module.naming.key_vault.name_unique
  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  enabled_for_disk_encryption = true
  network_acls = {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  role_assignments = {
    deployment_user_secrets = { #give the deployment user access to secrets
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = data.azurerm_client_config.current.object_id
    }
    deployment_user_keys = { #give the deployment user access to keys
      role_definition_id_or_name = "Key Vault Crypto Officer"
      principal_id               = data.azurerm_client_config.current.object_id
    }
  }

  wait_for_rbac_before_key_operations = {
    create = "60s"
  }

  wait_for_rbac_before_secret_operations = {
    create = "60s"
  }

  tags = local.tags

}

resource "azurerm_key_vault_secret" "admin_ssh_key" {
  key_vault_id = module.avm_res_keyvault_vault.resource_id
  name         = "azureuser-ssh-private-key"
  value        = tls_private_key.example_ssh.private_key_pem

  depends_on = [
    module.avm_res_keyvault_vault
  ]
}


# This is the module call
module "terraform_azurerm_avm_res_compute_virtualmachinescaleset" {
  source = "../../"
  # source             = "Azure/avm-res-compute-virtualmachinescaleset/azurerm"
  name                        = module.naming.virtual_machine_scale_set.name_unique
  resource_group_name         = azurerm_resource_group.this.name
  enable_telemetry            = var.enable_telemetry
  location                    = azurerm_resource_group.this.location
  admin_password              = "P@ssw0rd1234!"
  instances                   = 2
  sku_name                    = module.get_valid_sku_for_deployment_region.sku
  extension_protected_setting = {}
  user_data_base64            = null
  boot_diagnostics = {
    storage_account_uri = "" # Enable boot diagnostics
  }
  admin_ssh_keys = [(
    {
      id         = tls_private_key.example_ssh.id
      public_key = tls_private_key.example_ssh.public_key_openssh
      username   = "azureuser"
    }
  )]
  network_interface = [{
    name                      = "VMSS-NIC"
    network_security_group_id = azurerm_network_security_group.nic.id
    ip_configuration = [{
      name      = "VMSS-IPConfig"
      subnet_id = azurerm_subnet.subnet.id
    }]
  }]
  os_profile = {
    custom_data = base64encode(file("custom-data.yaml"))
    linux_configuration = {
      disable_password_authentication = false
      user_data_base64                = base64encode(file("user-data.sh"))
      admin_username                  = "azureuser"
      admin_ssh_key                   = toset([tls_private_key.example_ssh.id])
    }
  }
  source_image_reference = {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-LTS-gen2" # Auto guest patching is enabled on this sku.  https://learn.microsoft.com/en-us/azure/virtual-machines/automatic-vm-guest-patching
    version   = "latest"
  }
  extension = [{
    name                        = "HealthExtension"
    publisher                   = "Microsoft.ManagedServices"
    type                        = "ApplicationHealthLinux"
    type_handler_version        = "1.0"
    auto_upgrade_minor_version  = true
    failure_suppression_enabled = false
    settings                    = "{\"port\":80,\"protocol\":\"http\",\"requestPath\":\"/index.html\"}"
  }]
  tags = local.tags
  # Uncomment the code below to implement a VMSS Lock
  #lock = {
  #  name = "VMSSNoDelete"
  #  kind = "CanNotDelete"
  #}

  autoscale_enabled      = true
  autoscale_setting_name = "testautoscale"
  autoscale_setting = {
    profiles = [
      {
        name = "profile1"
        capacity = {
          default = 2
          minimum = 2
          maximum = 4
        }
        rules = [
          {
            metric_trigger = {
              metric_name      = "Percentage CPU"
              operator         = "LessThan"
              statistic        = "Average"
              threshold        = 10
              time_aggregation = "Average"
              time_grain       = "PT1M"
              time_window      = "PT2M"
            }
            scale_action = {
              cooldown  = "PT1M"
              direction = "Decrease"
              type      = "ChangeCount"
              value     = "1"
            }
          },
          {
            metric_trigger = {
              metric_name      = "Percentage CPU"
              operator         = "GreaterThan"
              statistic        = "Average"
              threshold        = 90
              time_aggregation = "Average"
              time_grain       = "PT1M"
              time_window      = "PT2M"
            }
            scale_action = {
              cooldown  = "PT1M"
              direction = "Increase"
              type      = "ChangeCount"
              value     = "1"
            }
          }
        ]
      }
    ]
    notification = {
      email = {
        custom_emails                         = ["abc@testing.com"]
        send_to_subscription_administrator    = false
        send_to_subscription_co_administrator = false
      }
      webhook = {
        service_uri = "https://webhooktesting.com"
      }
    }
  }



  depends_on = [azurerm_subnet_nat_gateway_association.this]
}



