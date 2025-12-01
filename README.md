# aspen-rs devcontainer
This repo contains the Dockerfile and shell scripts to create a linux environment to run aspen-rs. This was adapted from the weenix os-devcontainer repository (which is definitely overkill, but it's whatever).

## How to Use
1. Make sure Docker Daemon is running.
2. In the `container` directory, run `./build-container` in the terminal.
3. Back in the root (`aspen-rs-devcontainer`) directory, run `./run-container`.

The `home` directory is the root for the container, so it is recommended that `aspen-rs` is put in `home`.