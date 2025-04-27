# This file documents known items-yet-to-be-completed for the repo.

# Note

Over the next few versions tags will be kept consistent between tags for:
- This repo
- terraform-azure-simple-modules
- terraform-github-orchestration
- azure-infrastructure-live-template

# These items may apply to one or more of the repos listed above

- Add switch in TG file generation that detects when running as user to drive provider
- Add repo-to-repo triggering
- Catch up on tests
  - External test runner
- Better consistency between pre-boot and init terraform/terragrunt approach
- Better consistency between bootstrap and deployment terraform/terragrunt approach
- Integration with pkfiyah/hello-world-template
- Switch heredocs to scaffold
- Clean-up (self-destruct) script
  - From local repo or created repo
- Abstract cloud-specific logic
- Isolate and switch to plug-in for any extra smart repo github action workflow steps
- Pass full set of explicit versions through - improve this interface and echo chosen version set
  - Add a versioning paradigm to infra-live templates since this is not supported by github
- Thorough tracing for full process
  - Allow full process to be run locally
- Disable PII info output (By default? Things like Azure subscription ID)
- Bring verbosity into log files (optionally?)
- Switch from using ACA example to using modules explicitly
- Ensure failfast and reported failures
- Add "universe registry" support for local or remote handles
