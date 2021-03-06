resource "azuread_application" "delegateKvAadApp" {
  for_each = {
    for rg in var.rgConfig :
    rg.commonName => rg
    if rg.delegateKv == true
  }

  name = "${local.spNamePrefix}${local.groupNameSeparator}rg${local.groupNameSeparator}${var.subscriptionCommonName}${local.groupNameSeparator}${var.environmentShort}${local.groupNameSeparator}${each.key}${local.groupNameSeparator}kvreader"
}

resource "azuread_service_principal" "delegateKvAadSp" {
  for_each = {
    for rg in var.rgConfig :
    rg.commonName => rg
    if rg.delegateKv == true
  }

  application_id = azuread_application.delegateKvAadApp[each.key].application_id
}

resource "random_password" "delegateKvAadSpSecret" {
  for_each = {
    for rg in var.rgConfig :
    rg.commonName => rg
    if rg.delegateKv == true
  }

  length           = 48
  special          = true
  override_special = "!-_="

  keepers = {
    service_principal = azuread_service_principal.delegateKvAadSp[each.key].id
  }
}

resource "azuread_application_password" "delegateKvAadSpSecret" {
  for_each = {
    for rg in var.rgConfig :
    rg.commonName => rg
    if rg.delegateKv == true
  }

  application_object_id = azuread_application.delegateKvAadApp[each.key].id
  value                 = random_password.delegateKvAadSpSecret[each.key].result
  end_date              = timeadd(timestamp(), "87600h") # 10 years

  lifecycle {
    ignore_changes = [
      end_date
    ]
  }
}

resource "azurerm_key_vault_secret" "delegateKvAadSpKvSecret" {
  for_each = {
    for envResource in local.envResources :
    envResource.name => envResource
    if envResource.rgConfig.delegateKv == true
  }

  name = replace(azuread_service_principal.delegateKvAadSp[each.value.rgConfig.commonName].display_name, ".", "-")
  value = jsonencode({
    tenantId       = data.azurerm_subscription.current.tenant_id
    subscriptionId = data.azurerm_subscription.current.subscription_id
    clientId       = azuread_service_principal.delegateKvAadSp[each.value.rgConfig.commonName].application_id
    clientSecret   = random_password.delegateKvAadSpSecret[each.value.rgConfig.commonName].result
    keyVaultName   = azurerm_key_vault.delegateKv[each.value.name].name
  })
  key_vault_id = azurerm_key_vault.delegateKv[each.value.name].id

  depends_on = [
    azurerm_key_vault_access_policy.delegateKvApKvreaderSp,
    azurerm_key_vault_access_policy.delegateKvApOwnerSpn
  ]
}
