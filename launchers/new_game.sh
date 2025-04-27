#!/bin/bash

# ==============================================================================
# new_game.sh - Creates a new game environment.
# ==============================================================================

# Description:
#   This script automates the creation of a new game environment.

# Usage:
#   ./new_game.sh [game_prefix]

# Arguments:
#   game_prefix (optional):
#     - Used to generate a random game name if one is not provided.
#     - If omitted, a fully random name will be generated.

# Environment Variables (Required):
#   TF_VAR_github_org:
#     - The GitHub organization where the game repository will be created.
#   TF_VAR_github_pat:
#     - A GitHub Personal Access Token with repository creation permissions.
#   ARM_SUBSCRIPTION_ID:
#     - The Azure subscription ID where resources will be deployed.

# Environment Variables (Optional):
#   TASM_REF:
#     - The branch/tag reference where the terraform-azure-simple-modules will be referenced.

# Prerequisites:
#   - Azure CLI (az) must be installed and the user must be logged in. (Note that this CLI is included in the devcontainer)
#   - The user must have sufficient permissions to create repositories in the specified GitHub organization.
#   - The user must have sufficient permissions to create resources in the specified Azure subscription.

# ==============================================================================

# Verify the environment variables are set
if [ -z "$TF_VAR_github_org" ] || [ -z "$TF_VAR_github_pat" ] || [ -z "$ARM_SUBSCRIPTION_ID" ]; then
    echo "Please set the environment variables: TF_VAR_github_org, TF_VAR_github_pat, ARM_SUBSCRIPTION_ID"
    exit 1
fi

# Set optional environment variables if they are not set
if [ -z "$TASM_REF" ]; then
    export TASM_REF="v0.0.1-with-app"
fi

if [ -z "$TGO_REF" ]; then
    export TGO_REF="v0.0.1"
fi

# Check if the number of arguments is 1, use it as the game name prefix if so, and ask the user if they want to
# use a randomly generated pet name if not
if [ "$#" -eq 1 ]; then
    # Ensure the first argument contains only lowercase characters and hyphens; hyphens may not be the first or last character
    if ! [[ "$1" =~ ^[a-z-]+$ ]]; then
        echo "Invalid game prefix: $1"
        exit 1
    fi
    if [ "${1:0:1}" == "-" ] || [ "${1:${#1}-1}" == "-" ]; then
        echo "Invalid game prefix: $1"
        exit 1
    fi
    export GAME_PREFIX="$1"
else
    # Arrays of descriptors and animals
    descriptors=(
        "fluffy" "tiny" "majestic" "sneaky" "curious" "sleepy" "playful" "spotted"
        "striped" "golden" "silver" "silent" "loud" "happy" "sad" "brave" "shy"
    )

    animals=(
        "dog" "cat" "rabbit" "hamster" "ferret" "parrot" "snake" "turtle" "fish"
        "lizard" "gerbil" "guineapig" "mouse" "rat" "hedgehog" "chinchilla"
        "iguana" "frog" "newt" "salamander"
    )

    # Get the number of elements in each array
    descriptor_count=${#descriptors[@]}
    animal_count=${#animals[@]}

    # Generate random indices
    random_descriptor_index=$((RANDOM % descriptor_count))
    random_animal_index=$((RANDOM % animal_count))

    # Get the random descriptor and animal
    random_descriptor="${descriptors[$random_descriptor_index]}"
    random_animal="${animals[$random_animal_index]}"

    # Print the combined name
    export GAME_PREFIX="$random_descriptor-$random_animal"
fi

export GAME_NAME="${GAME_PREFIX}-game"

# Ask the user if they want to continue with the selected game name
echo "Selected game name: $GAME_NAME"
read -p "Do you want to continue with this game name? (y/n) " choice
if [ "$choice" != "y" ]; then
    echo "Exiting..."
    exit 0
fi

# Validate we have the Azure and Githuub credentials we need
az account set --subscription $ARM_SUBSCRIPTION_ID > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Failed to set Azure subscription to $ARM_SUBSCRIPTION_ID"
    exit 1
else
    export AZ_SUBSCRIPTION_NAME="$(az account show --query "name" --output tsv)"
    echo "Creatingg new game in Azure subscription $AZ_SUBSCRIPTION_NAME ( ID : $ARM_SUBSCRIPTION_ID )"
fi

export GH_AUTH_RESPONSE="$(curl -s -H "Authorization: token $TF_VAR_github_pat" https://api.github.com/user)"
if [[ "$GH_AUTH_RESPONSE" == *"login"* ]]; then
    echo "Creatingg new game as GitHub user: $(echo "$GH_AUTH_RESPONSE" | jq -r '.login')"
else
    echo "The GitHub PAT is not valid"
    exit 1
fi

# Note - in a subsequent increment we can likely wrap the process of self-bootstrapping state and creating the initial terragrunt
# structure in a single `scaffold` execution.

# Create our temporary directory and a nested directory where we will do our initial infrastructure bootstrapping
export TEMP_DIR="$(mktemp -d -t toy-azure-game-${GAME_PREFIX}-XXXX)"
export BOOTSTRAP_BASE_DIR="${TEMP_DIR}/${GAME_NAME}-bootstrap"
export STATE_BOOTSTRAP_DIR="${BOOTSTRAP_BASE_DIR}/state"
export TERRAGRUNT_BOOTSTRAP_DIR="${BOOTSTRAP_BASE_DIR}/terragrunt"
export SCAFFOLD_BOOTSTRAP_DIR="${BOOTSTRAP_BASE_DIR}/scaffold"
mkdir -p "${STATE_BOOTSTRAP_DIR}"
mkdir -p "${TERRAGRUNT_BOOTSTRAP_DIR}"
mkdir -p "${SCAFFOLD_BOOTSTRAP_DIR}"

echo "Creating temporary directory $TEMP_DIR for bootstrapping."

# Get our self-bootstrapped state uninitialized copy (TODO - use a real ref)
curl -H 'Cache-Control: no-cache' -s "https://raw.githubusercontent.com/je-sidestuff/terraform-azure-simple-modules/${TASM_REF}/scripts/self-bootstrapped-state/create_self_bootstrapped_state_config.sh" -o $STATE_BOOTSTRAP_DIR/create_self_bootstrapped_state_config.sh
chmod +x $STATE_BOOTSTRAP_DIR/create_self_bootstrapped_state_config.sh
cd $STATE_BOOTSTRAP_DIR && ./create_self_bootstrapped_state_config.sh $GAME_NAME $STATE_BOOTSTRAP_DIR $TERRAGRUNT_BOOTSTRAP_DIR && cd - 2>&1 >/dev/null
# TODO - we probably want better error detection/feedback here
cd $STATE_BOOTSTRAP_DIR && ./self_bootstrap.sh 2>&1 >/dev/null && cd - 2>&1 >/dev/null

# Get the scaffolding for the now bootstrapped state, the managed indentity, and the repo
# (Download scaffolder module, template simple main.tf, and execute - the state for the module will be thrown out)
export SBS_RG_NAME="$GAME_NAME-rg"
export SBS_SA_NAME="$(echo ${GAME_NAME}sa | sed 's/-//g')"
export SBS_SC_NAME="$(echo ${GAME_NAME}sc | sed 's/-//g')"
export REPO_NAME="$GAME_NAME-infra-live"

#         "init_payload_content_vars.yml": "InitPayloadContent: |\n  { \"subscription_id\": \"$ARM_SUBSCRIPTION_ID\", \"input_targets\": {} }"


cat << EOF > "${SCAFFOLD_BOOTSTRAP_DIR}/init_payload_content_vars.yml"
InitPayloadContent: |
  {
  "backend": {
    "resource_group": "$SBS_RG_NAME",
    "storage_account": "$SBS_SA_NAME",
    "container": "$SBS_SC_NAME"
  },
  "self_bootstrap" : {
    "subscription_id": "$ARM_SUBSCRIPTION_ID",
    "var_file_strings": {
      "init_payload_content_vars.yml": "InitPayloadContent: |\n  { \"subscription_id\": \"$ARM_SUBSCRIPTION_ID\", \"input_targets\": {} }"
    },
    "input_targets": {
      "managed_identity": {
        "repo": "je-sidestuff/terraform-azure-simple-modules",
        "path": "modules/iam/managed-identity",
        "ref": "$TASM_REF",
        "placement": {
          "region": "eastus",
          "env": "default",
          "subscription": "sandbox"
        },
        "vars": {
          "ResourceGroupName": "$SBS_RG_NAME",
          "NamingPrefix": "${GAME_NAME}",
          "FederatedIdentitySubjects": "\"[repo:${TF_VAR_github_org}/${REPO_NAME}:ref:refs/heads/main, repo:${TF_VAR_github_org}/${REPO_NAME}:ref:refs/tags/init]\"",
          "ContributorScope": "/subscriptions/$ARM_SUBSCRIPTION_ID"
        }
      },
      "infrastructure_live_repo": {
        "repo": "je-sidestuff/terraform-azure-simple-modules",
        "path": "modules/smart-template/infrastructure-live-deployment",
        "ref": "$TASM_REF",
        "placement": {
          "region": "eastus",
          "env": "default",
          "subscription": "sandbox"
        },
        "vars": {
          "Name": "${REPO_NAME}",
          "GithubOrg": "${TF_VAR_github_org}",
          "TimeoutInSeconds": "20"
        },
        "var_files": [
          "init_payload_content_vars.yml"
        ]
      }
    }
  },
  "deployment" : {
    "subscription_id": "$ARM_SUBSCRIPTION_ID",
    "var_file_strings": {
      "init_payload_content_vars.yml": "InitPayloadContent: |\n  { \"subscription_id\": \"$ARM_SUBSCRIPTION_ID\", \"input_targets\": {} }"
    },
    "input_targets": {
      "managed_identity": {
        "repo": "je-sidestuff/terraform-azure-simple-modules",
        "path": "examples/container-app/simple-webserver",
        "ref": "$TASM_REF",
        "placement": {
          "region": "eastus",
          "env": "default",
          "subscription": "sandbox"
        },
        "vars": {
          "NamingPrefix": "gm${GAME_NAME}"
        }
      }
    }
  }}
EOF

export ESCAPED_PAYLOAD_RECURSE="$(awk '{printf "%s\\n", $0}' ${SCAFFOLD_BOOTSTRAP_DIR}/init_payload_recurse.yml | sed 's/"/\\"/g')"

echo "Payload: ${ESCAPED_PAYLOAD_RECURSE}"

cat << EOF > "${SCAFFOLD_BOOTSTRAP_DIR}/main.tf"
module "scaffolding" {
  source = "github.com/je-sidestuff/terraform-github-orchestration//modules/terragrunt/scaffolder/from-json/?ref=$TGO_REF"

  input_json = <<EOT
  {
    "scaffolding_root": "${BOOTSTRAP_BASE_DIR}",
    "subscription_id": "$ARM_SUBSCRIPTION_ID",
    "var_files": [
      "init_payload_content_vars.yml"
    ],
    "input_targets": {
      "managed_identity": {
        "repo": "je-sidestuff/terraform-azure-simple-modules",
        "path": "modules/iam/managed-identity",
        "ref": "$TASM_REF",
        "placement": {
          "region": "eastus",
          "env": "default",
          "subscription": "sandbox"
        },
        "vars": {
          "ResourceGroupName": "$SBS_RG_NAME",
          "NamingPrefix": "${GAME_NAME}",
          "FederatedIdentitySubjects": "\"[repo:${TF_VAR_github_org}/${REPO_NAME}:ref:refs/heads/main, repo:${TF_VAR_github_org}/${REPO_NAME}:ref:refs/tags/init]\"",
          "ContributorScope": "/subscriptions/$ARM_SUBSCRIPTION_ID"
        }
      },
      "infrastructure_live_repo": {
        "repo": "je-sidestuff/terraform-azure-simple-modules",
        "path": "modules/smart-template/infrastructure-live-deployment",
        "ref": "$TASM_REF",
        "placement": {
          "region": "eastus",
          "env": "default",
          "subscription": "sandbox"
        },
        "vars": {
          "Name": "${REPO_NAME}",
          "GithubOrg": "${TF_VAR_github_org}",
          "TimeoutInSeconds": "300"
        },
        "var_files": [
          "init_payload_content_vars.yml"
        ]
      }
    }
  }
EOT
}
EOF

cd $SCAFFOLD_BOOTSTRAP_DIR && terraform init && terraform apply --auto-approve && cd -

# Apply the scaffolded terragrunt
cd $TERRAGRUNT_BOOTSTRAP_DIR && terragrunt run-all apply --terragrunt-non-interactive && cd -

# The final step of the infra-live leaf node is to push the post-init tag, kicking off the next activity column
