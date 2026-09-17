# ============================================================================
#  Logic Apps — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-logic"                      # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_logic_app_workflow" "lab" {    # the Logic App (a workflow)
  name                = "workflow-lab"          # the Logic App's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG

  # The WORKFLOW: a JSON document (Request trigger → Respond action)
  # This is the "as-code" definition of the visual workflow.
  workflow_schema = jsonencode({                  # the workflow's JSON schema
    "$schema" = "https://schema.management.azure.com/schemas/2015-02-01/workflowdefinition.json#"   # the schema version
    "contentVersion" = "1.0.0.0"                 # the content version
    "parameters"   = {}                           # the workflow's parameters (none)
    "triggers" = {                                 # the TRIGGERS
      "manual" = {                                 # a manual (HTTP) trigger
        "type" = "Request"                         # a Request trigger (invoked over HTTP)
      }
    }
    "actions" = {                                  # the ACTIONS (what to do)
      "Respond" = {                                # a Respond action
        "type"   = "HttpResponse"                  # respond over HTTP
        "inputs" = {                                # the response
          "statusCode" = 200                        # the status code
          "body"       = "Hello from a Logic App"  # the response body
        }
      }
    }
    "runsOn" = ""                                  # where it runs ("" = serverless)
  })
}
