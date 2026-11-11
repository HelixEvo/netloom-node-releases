# NetLoom Node for Ubuntu

This repository distributes the NetLoom compute agent for Ubuntu Server 24.04 and 26.04 amd64. The customer host initiates outbound HTTPS connections to the NetLoom dashboard. Use a dedicated host with systemd, Ubuntu Universe enabled, and /dev/kvm for QEMU guests.

## Install

On dashboard 0.9.14 or later, sign in with your licensed account and choose **My nodes → Add my node**. Enter a name for this Ubuntu host. Copy the configuration shown once and keep it on your own machine for the installer. An administrator can also register an outbound node and assign it to your account. On dashboard 0.9.13, an administrator must perform registration.

Each registration is for one compute host. Your device allowance is shared across every node you own, including devices started by people you have shared a node with.

After the operator publishes the reviewed node and QEMU runtime releases, download the installer on the fresh host:

```bash
curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' \
  https://github.com/HelixEvo/netloom-node-releases/releases/latest/download/install.sh \
  --output install-netloom-node.sh && sudo bash ./install-netloom-node.sh
```

The installer downloads the Debian package for the release marked **Latest**. It checks the release asset's GitHub-reported SHA-256 digest, size, package name, version and architecture before invoking APT. Before first startup, it checks QEMU using the runtime helper packaged with the node. On Ubuntu 26.04 with the affected QEMU package, it downloads and verifies the separately released AHCI repair; no compilation runs on your host. An already repaired host is left in place. Ubuntu 24.04 uses its distribution QEMU. Unknown Ubuntu 26.04 QEMU versions require review and are never automatically downgraded. At first setup, paste the full configuration block from the dashboard. The input is hidden. Press Enter on a blank line to finish. The installer writes it to `/etc/blocpow/netloom.env` with mode `0600` and starts the node. Each compute host has its own UUID and credentials. The public release contains placeholders only.

If you already have the dashboard-issued configuration in a protected local file, use `sudo bash ./install-netloom-node.sh --config /path/to/node.env`. The optional `--qemu-bundle /path/to/qemu-ahci-ubuntu26.04-amd64.zip` uses a local copy of the exact verified runtime release. If you defer configuration, edit `/etc/blocpow/netloom.env` with `sudoedit`, then run `sudo systemctl enable --now docker.service openvswitch-switch.service netloom-node.service`.

Check the installed version with `/usr/bin/netloom-node --version`. Confirm **Online** in the dashboard and open the node's image inventory to exercise the return path.

## Updates

Drain new work and let running jobs finish. Run the install command again during your maintenance window to fetch the latest stable package. Existing credentials, host state and guest storage are preserved. If QEMU needs replacement, stop all QEMU guests first; the helper refuses to replace a running hypervisor. A host already using the reviewed repair does not reinstall it. After upgrading, restart the agent with `sudo systemctl restart netloom-node.service` and check its reported version and inventory. Keep hosts installed from a manual source checkout on their existing update procedure.

## Runtime release maintenance

The dedicated `qemu-10.2.1-ubuntu3.3-netloom1` release must contain the verified
`qemu-ahci-ubuntu26.04-amd64.zip` and `qemu-ahci-corresponding-source.tar.xz`.
Publish it **without marking it Latest**. The installer selects the normal node
release marked Latest and pins the QEMU bundle to its separately reviewed tag
and SHA-256. The node workflow checks that the QEMU assets exist before building
a new node package. Publish the reviewed installer changes before tagging the
private node release.

On an installed node, run
`sudo bash /usr/lib/netloom-node/install-qemu-runtime.sh --check` to inspect the
runtime. After saving and stopping QEMU guests, `--install` installs the selected
repair, retaining original packages and rollback instructions. The dashboard's
agent updater does not automatically replace QEMU. No APT hold is installed;
review future Ubuntu QEMU updates before rolling them across lab hosts.

Use an `agent/<task-name>` branch from `dev`, PR into `dev`, then a separate
reviewed PR to `main`. The release preparation does not merge or deploy changes.

Copyright © 2026 Marcus & Rhys Phillips (blocpow.io). All rights reserved. Third-party components are distributed under their respective licences; notices accompany the Debian package.

