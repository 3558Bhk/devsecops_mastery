# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "project_id" {                             # output: the project's id
  value       = azuredevops_project.lab.id              # the id
  description = "the project's id (used by repos/pipelines)"   # the container
}

output "repo_id" {                                # output: the repo's id
  value       = azuredevops_git_repository.app.id       # the id
  description = "the repo's id (used by pipelines)"   # the source
}
