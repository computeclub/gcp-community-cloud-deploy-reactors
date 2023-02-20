include {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "github.com/computeclub/gcp-cloud-deploy-notifiers//terraform/cloud-deploy-notifier?ref=v0.1.1"
  # source = "${find_in_parent_folders("gcp-cloud-deploy-notifiers")}//terraform/cloud-deploy-notifier"
  before_hook "before_hook" {
    commands = ["apply"]
    execute = [
      "gcloud",
      "builds",
      "submit",
      "--config=${local.notifier_path}/cloudbuild.yaml",
      "--project=${local.config.locals.project_id}",
      "--substitutions=_REGISTRY_REPO_URL=${dependency.cloud_deploy_foundation.outputs.artifact_registry_repo_endpoint}",
      "${local.notifier_path}/"
    ]
  }
}

locals {
  config        = read_terragrunt_config(find_in_parent_folders("config.hcl"))
  notifier_path = "${find_in_parent_folders("gcp-cloud-deploy-notifiers")}/notifiers/release-auto-promoter"
}

dependency "cloud_deploy_foundation" {
  config_path = "${find_in_parent_folders("terragrunt")}/cloud-deploy-foundation"
  mock_outputs = {
    artifact_registry_repo = {
      location = "foo"
      name     = "bar"
      format   = "docker"
      project  = "my-project-id"
    }
    cloud_deploy_pubsub_topics = {
      clouddeploy-resources  = {}
      clouddeploy-operations = {}
      clouddeploy-approvals  = {}
    }
  }
}

inputs = {
  artifact_registry_repo = dependency.cloud_deploy_foundation.outputs.artifact_registry_repo
  cloud_deploy_notification_subscriptions = [
    {
      topic  = "clouddeploy-operations"
      filter = "attributes.Action = \"Succeed\" AND attributes.ResourceType = \"Rollout\""
    },
  ]
  env_vars = [
    {
      name  = "LOG_LEVEL"
      value = "INFO"
    },
    {
      name = "SRC_SHA1"
      value = sha1(
        join(
          "",
          [
            for f in fileset(
              "${local.notifier_path}/",
              "**"
            ) : filesha1("${local.notifier_path}/${f}")
          ]
        )
      )
    },
  ]
  notifier_name = "release-auto-promoter"
  project_id    = local.config.locals.project_id
  region        = "us-central1"
  workload_sa_project_roles = [
    "roles/clouddeploy.releaser",
  ]
}
