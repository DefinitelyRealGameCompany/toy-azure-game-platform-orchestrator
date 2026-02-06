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
    export TASM_REF="support_self_bootstrapped_state_scaffold_fully" # TODO: Remove
fi

if [ -z "$TGO_REF" ]; then
    export TGO_REF="v0.0.1"
    export TGO_REF="finish_scaffold_generators_and_backends" # TODO: Remove
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
    echo "Creating new game in Azure subscription $AZ_SUBSCRIPTION_NAME ( ID : $ARM_SUBSCRIPTION_ID )"
fi

export GH_AUTH_RESPONSE="$(curl -s -H "Authorization: token $TF_VAR_github_pat" https://api.github.com/user)"
if [[ "$GH_AUTH_RESPONSE" == *"login"* ]]; then
    echo "Creating new game as GitHub user: $(echo "$GH_AUTH_RESPONSE" | jq -r '.login')"
else
    echo "The GitHub PAT is not valid"
    exit 1
fi



####################################################################################################################################
## New Method Start
####################################################################################################################################

# Create our temporary directory and the nested bootstrap terragrunt tree - create the scaffolder first which will scaffold everything else
export TEMP_DIR="$(mktemp -d -t toy-azure-game-${GAME_PREFIX}-XXXX)"
export BOOTSTRAP_BASE_DIR="${TEMP_DIR}/${GAME_NAME}-bootstrap"
export TERRAGRUNT_BOOTSTRAP_DIR="${BOOTSTRAP_BASE_DIR}/terragrunt"
export TERRAGRUNT_SCAFFOLD_DIR="${BOOTSTRAP_BASE_DIR}/terragrunt/scaffold"
export TERRAGRUNT_STATE_BOOTSTRAP_DIR="${BOOTSTRAP_BASE_DIR}/terragrunt/sandbox/eastus/default/state/self_bootstrapped_state"
export STATE_BOOTSTRAP_DIR="${BOOTSTRAP_BASE_DIR}/terragrunt/scaffold"
mkdir -p "${TERRAGRUNT_SCAFFOLD_DIR}"

export SBS_RG_NAME="$GAME_NAME-rg"
export SBS_SA_NAME="$(echo ${GAME_NAME}sa | sed 's/-//g')"
export SBS_SC_NAME="$(echo ${GAME_NAME}sc | sed 's/-//g')"
export REPO_NAME="$GAME_NAME-infra-live"

# Define the content to be created in the bootstrap tree:
# - Scaffolder
# - Self-Bootstrapped State
# - Managed Identity
# - Infra Live Repo

# TODO - Introduce a default scaffolding library to reduce verbosity.
#        We should be able to use a single string to pull fully-defaulted terragrunt units.

# First create the self-bootstrap perspective of the bootstrap content (to be run inside the created repo)

MANAGED_IDENTITY_JSON=$(cat <<EOF
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
  }
EOF
)

SELF_BOOTSTRAPPED_STATE_JSON=$(cat <<EOF
"self_bootstrapped_state": {
    "repo": "je-sidestuff/terraform-azure-simple-modules",
    "path": "modules/state/self-bootstrapped-state",
    "ref": "$TASM_REF",
    "placement": {
      "region": "eastus",
      "env": "default",
      "subscription": "sandbox"
    },
    "vars": {
      "ResourceGroupName": "${SBS_RG_NAME}",
      "StorageAccountName": "${SBS_SA_NAME}",
      "RootContainerName": "${SBS_SC_NAME}",
      "IncludeRoot": "true"
    }
  }
EOF
)

INFRA_LIVE_REPO_SELF_BOOTSTRAP_JSON=$(cat <<EOF
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
      "TimeoutInSeconds": "30",
      "SelfBootstrapContentJsonB64": "e30=",
      "DeployContentJsonB64": "e30="
    },
    "var_files": []
  }
EOF
)

cat << EOF > "${TERRAGRUNT_SCAFFOLD_DIR}/self_bootstrap_nodes.json"
{
  "input_targets": {
    ${SELF_BOOTSTRAPPED_STATE_JSON},
    ${MANAGED_IDENTITY_JSON},
    ${INFRA_LIVE_REPO_SELF_BOOTSTRAP_JSON}
  }
}
EOF

export SELF_BOOTSTRAP_SCAFFOLD_JSON_B64="$(base64 -w0 ${TERRAGRUNT_SCAFFOLD_DIR}/self_bootstrap_nodes.json)"

# Define the content to be created in the deployment tree:
# - (For now only example)
# - ACR
# - ACR Image Build
# - ACA Environment
# - Game Client ACA

TMP_ACA_EXAMPLE_JSON=$(cat <<EOF
"app": {
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
EOF
)

cat << EOF > "${TERRAGRUNT_SCAFFOLD_DIR}/deploy_nodes.json"
{
  "input_targets": {
    ${TMP_ACA_EXAMPLE_JSON}
  }
}
EOF

export DEPLOY_SCAFFOLD_JSON_B64="$(base64 -w0 ${TERRAGRUNT_SCAFFOLD_DIR}/deploy_nodes.json)"

# Next create the orchestrator perspective of the bootstrap content

INFRA_LIVE_REPO_ORCHESTRATOR_JSON=$(cat <<EOF
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
      "TimeoutInSeconds": "300",
      "SelfBootstrapContentJsonB64": "$SELF_BOOTSTRAP_SCAFFOLD_JSON_B64",
      "DeployContentJsonB64": "$DEPLOY_SCAFFOLD_JSON_B64"
    },
    "var_files": []
  }
EOF
)


SELF_BOOTSTRAPPED_STATE_ORCHESTRATOR_JSON=$(cat <<EOF
"self_bootstrapped_state": {
    "repo": "je-sidestuff/terraform-azure-simple-modules",
    "path": "modules/state/self-bootstrapped-state",
    "ref": "$TASM_REF",
    "placement": {
      "region": "eastus",
      "env": "default",
      "subscription": "sandbox"
    },
    "vars": {
      "ResourceGroupName": "${SBS_RG_NAME}",
      "StorageAccountName": "${SBS_SA_NAME}",
      "RootContainerName": "${SBS_SC_NAME}",
      "IncludeRoot": "false"
    }
  }
EOF
)

# We may not actually end up using the json file - let's keep it in the chain for visibility for now.
# Note that we also don't need to explicitly define the key here, but we will for consistency.
cat << EOF > "${TERRAGRUNT_SCAFFOLD_DIR}/orchestrator_bootstrap_nodes.json"
{
  "input_targets": {
    ${SELF_BOOTSTRAPPED_STATE_ORCHESTRATOR_JSON},
    ${MANAGED_IDENTITY_JSON},
    ${INFRA_LIVE_REPO_ORCHESTRATOR_JSON}
  },
  "backend_generators": {
    "azure": {
      "backend_type": "azure",
      "backend_subtype": "user",
      "arguments": {
        "resource_group_name": "${SBS_RG_NAME}",
        "storage_account_name": "${SBS_SA_NAME}",
        "container_name": "${SBS_SC_NAME}", 
        "key": "root.tfstate"
      }
    }
  },
  "provider_generators": {
    "azure": {
      "provider_type": "azure",
      "provider_subtype": "user",
      "arguments": {
        "subscription_id": "${ARM_SUBSCRIPTION_ID}"
      }
    }
  },
  "subscription_id": "${ARM_SUBSCRIPTION_ID}",
  "scaffolding_root": "${BOOTSTRAP_BASE_DIR}"
}
EOF

export ORCHESTRATOR_SCAFFOLD_JSON_B64="$(base64 -w0 ${TERRAGRUNT_SCAFFOLD_DIR}/orchestrator_bootstrap_nodes.json)"

# Scaffold our scaffolder so it can scaffold the remaining tree
cd $TERRAGRUNT_SCAFFOLD_DIR
terragrunt scaffold github.com/je-sidestuff/terraform-github-orchestration//modules/terragrunt/scaffolder/from-json?ref=$TGO_REF --var=InputJsonB64="$ORCHESTRATOR_SCAFFOLD_JSON_B64" --terragrunt-non-interactive
terragrunt run-all apply --terragrunt-non-interactive
cd -

echo "Scaffolding complete in: ${TERRAGRUNT_SCAFFOLD_DIR}"

cd $TERRAGRUNT_STATE_BOOTSTRAP_DIR
./self_bootstrap.sh
cd -


echo "State bootstrapped complete in: ${TERRAGRUNT_STATE_BOOTSTRAP_DIR}"

echo "#!/bin/bash" > "${BOOTSTRAP_BASE_DIR}/destroy.sh"
echo "Destroy commands:"
echo "# Destroy commands:" >> "${BOOTSTRAP_BASE_DIR}/destroy.sh"
echo "cd ${TERRAGRUNT_BOOTSTRAP_DIR}; terragrunt run-all destroy --terragrunt-non-interactive; cd -"
echo "cd ${TERRAGRUNT_BOOTSTRAP_DIR}; terragrunt run-all destroy --terragrunt-non-interactive; cd -" >> "${BOOTSTRAP_BASE_DIR}/destroy.sh"
echo "cd ${TERRAGRUNT_STATE_BOOTSTRAP_DIR}; ./destroy_state.sh; cd -"
echo "cd ${TERRAGRUNT_STATE_BOOTSTRAP_DIR}; ./destroy_state.sh; cd -" >> "${BOOTSTRAP_BASE_DIR}/destroy.sh"
echo "${BOOTSTRAP_BASE_DIR}/destroy.sh"
chmod 755 "${BOOTSTRAP_BASE_DIR}/destroy.sh"

if [ "${SKIP_CREATE_STACK}" != "true" ]; then
    echo "SKIP_CREATE_STACK is not set - creating stack."
    cd "${BOOTSTRAP_BASE_DIR}/terragrunt/sandbox/"
    terragrunt run-all apply --terragrunt-non-interactive
    cd -
fi
