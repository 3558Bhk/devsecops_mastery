# ============================================================================
#  Azure DevOps — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azuredevops_project" "lab" {            # the project
  name                = "LabProject"            # the project's name
  description         = "A lab project"         # the project's description
  visibility          = "private"               # the visibility (private)
  version_control     = "Git"                   # the version control (Git)
  work_item_template  = "Agile"                 # the work item template (Agile)

  features = {                                  # which features are enabled
    "boards"       = "enabled"                   # work items
    "repositories" = "enabled"                   # git repos
    "pipelines"    = "enabled"                   # CI/CD
    "artifacts"    = "enabled"                   # artifact feeds
  }
}

resource "azuredevops_git_repository" "app" {     # the repo
  name                = "app-repo"              # the repo's name
  project_id          = azuredevops_project.lab.id   # which project
  default_branch      = "main"                  # the default branch

  initialization {                                # how to initialize the repo
    init_type = "Clean"                           # start clean (empty)
  }
}

resource "azuredevops_variable_group" "shared" {  # the variable group
  name                = "shared-variables"      # the group's name
  project_id          = azuredevops_project.lab.id   # which project
  allow_access        = true                    # pipelines can use this group

  variable {                                      # a plain variable
    name  = "environment"                        # the variable's name
    value = "dev"                                # the value
  }

  variable {                                      # a SECRET variable (not shown in the UI)
    name     = "db_password"                     # the variable's name
    value    = "SuperSecret-123"                 # the value (CHANGE)
    is_secret = true                              # it's a secret (encrypted)
  }
}
