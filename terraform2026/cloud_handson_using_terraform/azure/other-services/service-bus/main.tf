# ============================================================================
#  Service Bus — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-sb"                         # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_servicebus_namespace" "lab" {  # the namespace
  name                = "sb-lab"                # the namespace's name (globally unique)
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  sku                 = "Basic"                 # the SKU (Basic = the cheapest)
}

resource "azurerm_servicebus_queue" "work" {     # the queue
  name                = "queue-work"            # the queue's name
  namespace_id        = azurerm_servicebus_namespace.lab.id   # which namespace
  max_delivery_count  = 10                      # the max delivery count (then → DLQ)
  requires_session    = false                   # (false = no ordered sessions)
}

resource "azurerm_servicebus_topic" "events" {   # the topic
  name                = "topic-events"          # the topic's name
  namespace_id        = azurerm_servicebus_namespace.lab.id   # which namespace

}

resource "azurerm_servicebus_subscription" "alerts" {   # the subscription
  name                = "sub-alerts"            # the subscription's name
  topic_id            = azurerm_servicebus_topic.events.id   # which topic
  max_delivery_count  = 10                      # the max delivery count (then → DLQ)

}

resource "azurerm_servicebus_subscription_rule" "high" {   # the message filter (v5: separate resource)
  name              = "rule-high"                       # the rule name
  subscription_id   = azurerm_servicebus_subscription.alerts.id   # which subscription
  filter_type       = "SqlFilter"                       # a SQL expression filter
  sql_filter        = "security = 'high'"             # the filter (a SQL expression on the message)
}
