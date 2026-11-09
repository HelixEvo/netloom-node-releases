# NetLoom Node for Ubuntu

This repository distributes the NetLoom compute agent for Ubuntu Server 24.04 amd64. The customer host initiates outbound HTTPS connections to the NetLoom dashboard. Use a dedicated host with systemd, Ubuntu Universe enabled, and /dev/kvm for QEMU guests.

## Install

On dashboard 0.9.14 or later, sign in with your licensed account and choose **My nodes → Add my node**. Enter a name for this Ubuntu host. Copy the configuration shown once and keep it on your own machine for the installer. An administrator can also register an outbound node and assign it to your account. On dashboard 0.9.13, an administrator must perform registration.

Each registration is for one compute host. Your device allowance is shared across every node you own, including devices started by people you have shared a node with.

After the operator publishes the first stable release of this repository, download the installer on the fresh host:

```bash
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' \
  https://github.com/HelixEvo/netloom-node-releases/releases/latest/download/install.sh \
  --output install-netloom-node.sh && sudo bash ./install-netloom-node.sh
```

The installer downloads the Debian package for the release marked **Latest**. It checks the release asset's GitHub-reported SHA-256 digest, size, package name, version and architecture before invoking APT. At first setup, paste the full configuration block from the dashboard. The input is hidden. Press Enter on a blank line to finish. The installer writes it to `/etc/blocpow/netloom.env` with mode `0600` and starts the node. Each compute host has its own UUID and credentials. The public release contains placeholders only.

If you already have the dashboard-issued configuration in a protected local file, use `sudo bash ./install-netloom-node.sh --config /path/to/node.env`. If you defer configuration, edit `/etc/blocpow/netloom.env` with `sudoedit`, then run `sudo systemctl enable --now docker.service openvswitch-switch.service netloom-node.service`.

Check the installed version with `/usr/bin/netloom-node --version`. Confirm **Online** in the dashboard and open the node's image inventory to exercise the return path.

## Updates

Drain new work and let running jobs finish. Run the install command again during your maintenance window to fetch the latest stable package. Existing credentials, host state and guest storage are preserved. After upgrading, restart the agent with `sudo systemctl restart netloom-node.service` and check its reported version and inventory. Keep hosts installed from a manual source checkout on their existing update procedure.

Copyright © 2026 Marcus & Rhys Phillips (blocpow.io). All rights reserved. Third-party components are distributed under their respective licences; notices accompany the Debian package.
