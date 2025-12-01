#!/bin/bash
# Smart container launcher for your Rust async runtime dev environment.
# Defaults to running an amd64 Linux container even on Apple Silicon.
# Automatically detects available host CPUs and sets CPU limits/pinning
# unless the user overrides them.

set -e
cd "$(dirname "$0")"

# --- Configurable defaults ---
IMAGE_NAME="aspen-rs-image"
TAG="latest"
CONTAINER_NAME="aspen-rs-dev"
PLATFORM="linux/amd64"
HOST_ARCH="$(uname -m)"
VERBOSE=false

# CPU options (auto-detected unless overridden)
CPU_LIMIT=""
CPUSET=""
AUTO_CPU_MODE=true

# --- Detect usable host CPUs ---
# macOS: sysctl -n hw.ncpu
# Linux: nproc
if [[ "$(uname)" == "Darwin" ]]; then
    HOST_CPUS=$(sysctl -n hw.ncpu)
else
    HOST_CPUS=$(nproc)
fi

# --- Default: use all host CPUs and pin to 0-(n-1) ---
AUTO_CPU_LIMIT="--cpus=${HOST_CPUS}"
AUTO_CPUSET="--cpuset-cpus=0-$((HOST_CPUS-1))"

# --- Parse flags ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -V|--verbose)
            VERBOSE=true
            shift
            ;;
        --cpus)
            CPU_LIMIT="--cpus=$2"
            AUTO_CPU_MODE=false
            shift 2
            ;;
        --pin|--cpuset)
            CPUSET="--cpuset-cpus=$2"
            AUTO_CPU_MODE=false
            shift 2
            ;;
        -x|--x86|--amd64|--x86_64)
            PLATFORM="linux/amd64"
            TAG="latest"
            shift
            ;;
        -a|--arm|--arm64)
            if [[ "$HOST_ARCH" == "arm64" || "$HOST_ARCH" == "aarch64" ]]; then
                PLATFORM="linux/arm64"
                TAG="arm64"
                shift
            else
                echo "Error: --arm64 builds only supported on ARM hosts." >&2
                exit 1
            fi
            ;;
        -t|--tag)
            TAG="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo
            echo "CPU control:"
            echo "  --cpus N             Limit container to N CPUs (overrides auto detection)"
            echo "  --pin 0-3            Pin container to specific CPUs (overrides auto pinning)"
            echo
            echo "Platform:"
            echo "  --x86                Run amd64 container (default)"
            echo "  --arm                Run arm64 container (Apple Silicon only)"
            echo
            echo "  --tag <name>         Run with a specific image tag"
            echo "  -V, --verbose        Print full docker command"
            echo
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# --- Auto CPU settings unless overridden ---
if $AUTO_CPU_MODE; then
    CPU_LIMIT="$AUTO_CPU_LIMIT"
    CPUSET="$AUTO_CPUSET"
fi

# --- Validation: Ensure pinning / limits do not exceed host cores ---
if [[ -n "$CPU_LIMIT" ]]; then
    # Strip flag prefix
    CPU_LIMIT_VAL=$(echo "$CPU_LIMIT" | sed 's/--cpus=//')
    # Extract integer part (ignore fractional CPUs)
    CPU_LIMIT_INT=${CPU_LIMIT_VAL%.*}
    if (( CPU_LIMIT_INT > HOST_CPUS )); then
        echo "Warning: Requested --cpus=$CPU_LIMIT_VAL exceeds available host CPUs ($HOST_CPUS)."
        echo "         Docker will clamp the value."
    fi
fi

if [[ -n "$CPUSET" ]]; then
    CPUSET_RANGE=$(echo "$CPUSET" | sed 's/--cpuset-cpus=//')
    LAST_CPU=$(echo "$CPUSET_RANGE" | awk -F'-' '{print $NF}')
    if (( LAST_CPU >= HOST_CPUS )); then
        echo "Error: Requested pin range $CPUSET_RANGE exceeds host CPU count ($HOST_CPUS)." >&2
        exit 1
    fi
fi

# --- Summary ---
if $VERBOSE; then
    echo "Launching container:"
    echo "  Host arch      : $HOST_ARCH"
    echo "  Docker platform: $PLATFORM"
    echo "  Host CPUs      : $HOST_CPUS"
    echo "  Using CPUs     : ${CPU_LIMIT#--cpus=}"
    echo "  CPU pinning    : ${CPUSET#--cpuset-cpus=}"
    echo "  Image tag      : ${IMAGE_NAME}:${TAG}"
    echo "  Container name : ${CONTAINER_NAME}"
    echo
fi

# --- SSH agent forwarding for macOS ---
SSH_ARGS=()
if [[ -n "$SSH_AUTH_SOCK" && "$(uname)" == "Darwin" ]]; then
    SSH_ARGS+=(
        "-v" "/run/host-services/ssh-auth.sock:/run/host-services/ssh-auth.sock"
        "-e" "SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock"
    )
fi

# --- Development workspace mount ---
WORKDIR="$(pwd)"
PROJECT_HOME="$WORKDIR/home"
mkdir -p "$PROJECT_HOME"

# --- Reuse container if running ---
EXISTING_ID=$(docker ps -q -f name="$CONTAINER_NAME")
if [[ -n "$EXISTING_ID" ]]; then
    echo "* Reusing running container $CONTAINER_NAME ($EXISTING_ID)"
    exec docker exec -it "$CONTAINER_NAME" /bin/bash
fi

# --- Build final docker run command ---
CMD=(
    docker run -it --rm
    --name "$CONTAINER_NAME"
    --platform "$PLATFORM"
    --privileged
    --cap-add=SYS_PTRACE
    --security-opt seccomp=unconfined
    --net=host
    -v "$PROJECT_HOME:/home"
    $CPU_LIMIT
    $CPUSET
    "${SSH_ARGS[@]}"
    "${IMAGE_NAME}:${TAG}"
)

if $VERBOSE; then
    echo ""
    echo "Full docker command:"
    printf '%q ' "${CMD[@]}"
    echo ""
    echo ""
fi

exec "${CMD[@]}"
