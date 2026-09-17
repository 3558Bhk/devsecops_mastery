terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # Azure provider, any 5.x
  }
}

provider "azurerm" {                             # configure the Azure provider
  features {}                                    # required in v5
}

resource "azurerm_resource_group" "msg" {        # the resource group
  name     = "${var.project}-msg-rg"             # e.g. msg-msg-rg
  location = var.location                        # from the input
}

# ── the namespace: the container that holds topics + queues ───────────────────

resource "azurerm_servicebus_namespace" "bus" {  # the Service Bus namespace
  name                = "${var.project}-sb-2026"  # the namespace's name (globally unique)
  location            = var.location              # same location
  resource_group_name = azurerm_resource_group.msg.name   # which group
  sku                 = "Basic"                   # Basic = cheapest (Standard adds advanced features)
}

# Authorization rules = the namespace's keys (Send / Listen / Manage)
resource "azurerm_servicebus_namespace_authorization_rule" "send" {   # a rule that may SEND
  name         = "send"                            # the rule's name
  namespace_id = azurerm_servicebus_namespace.bus.id   # which namespace
  send         = true                             # may send
  listen       = false                            # may not receive
  manage       = false                            # may not administer
}

resource "azurerm_servicebus_namespace_authorization_rule" "listen" { # a rule that may RECEIVE
  name         = "listen"                          # the rule's name
  namespace_id = azurerm_servicebus_namespace.bus.id   # which namespace
  send         = false                             # may not send
  listen       = true                              # may receive
  manage       = false                             # may not administer
}

# ── the pub/sub side: topic + subscriptions ───────────────────────────────────

resource "azurerm_servicebus_topic" "orders" {    # the topic: the fan-out point
  name           = "orders"                       # the topic's name
  namespace_id   = azurerm_servicebus_namespace.bus.id   # which namespace (by ID in this provider version)
}

resource "azurerm_servicebus_subscription" "billing" {   # subscription 1: the billing consumer's view
  name               = "billing"                   # the subscription's name
  topic_id           = azurerm_servicebus_topic.orders.id   # which topic (by ID)
  max_delivery_count = 3                           # 3 failed deliveries → dead-letter (poison handling)

  # (rule blocks here would filter which messages this subscription gets — e.g. only
  #  messages with property "priority" = "high" — kept simple in this lab)
}

resource "azurerm_servicebus_subscription" "inventory" { # subscription 2: the inventory consumer's view
  name               = "inventory"                 # the subscription's name
  topic_id           = azurerm_servicebus_topic.orders.id   # same topic
  max_delivery_count = 3                           # same poison handling
}

# ── the work-queue side: a queue with a dead-letter path ──────────────────────

resource "azurerm_servicebus_queue" "archive" {    # the queue: a work buffer
  name                = "archive"                  # the queue's name
  namespace_id        = azurerm_servicebus_namespace.bus.id   # which namespace (by ID)
  max_delivery_count  = 5                           # 5 failed deliveries → dead-letter
  default_message_ttl = "P1D"                       # a message older than 24h expires (ISO 8601 duration)
  lock_duration       = "PT30S"                     # a received message is hidden for 30s (ISO 8601 duration)
  dead_lettering_on_message_expiration = true        # expired messages → DLQ (so you can inspect them)
}
