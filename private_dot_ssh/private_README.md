# SSH Key Inventory

This directory contains public SSH keys and related SSH configuration files.

| File | Purpose | Algorithm |
| --- | --- | --- |
| `tpm-iszkiba-g.pub` | Public SSH key for host `iszkiba-g`, backed by TPM and PIV | ECDSA |
| `tpm-iszkiba-r.pub` | Public SSH key for host `iszkiba-r`, backed by TPM and PIV | ECDSA |
| `legacy-iszkiba.pub` | Legacy public SSH key for the `iszkiba@gmail.com` SourceForge account | RSA |
| `yubikey-piv-9a.pub` | YubiKey PIV slot `9a` | ECDSA |
| `yubikey-piv-9c.pub` | YubiKey PIV slot `9c` | RSA |
| `yubikey-piv-9d.pub` | YubiKey PIV slot `9d` | ECDSA |
| `yubikey-piv-9e.pub` | YubiKey PIV slot `9e` | RSA |
| `yubikey-blue-auxiliary.pub` | YubiKey security key (blue) — auxiliary key | ED25519-SK |
| `yubikey-blue-primary.pub` | YubiKey security key (blue) — primary key | ED25519-SK |
| `yubikey-gpg.pub` | YubiKey GPG SSH key | ED25519 |
| `token2-mini-274.pub` | Token2 mini FIDO2 security key (resident) | ED25519-SK |
| `token2-mini-348.pub` | Token2 mini FIDO2 security key (resident) | ED25519-SK |
| `token2-769.pub` | Token2 FIDO2 security key (resident) | ED25519-SK |

## Configuration files

| File | Purpose |
| --- | --- |
| `allowed_signers` | Trusted public keys for SSH signature verification (git commit/tag signing, `ssh-keygen -Y verify`). Entries scoped to `namespaces="git"`. |
| `config`, `config.d/` | SSH client configuration. |
| `authorized_keys` | Public keys permitted to log in to this account. |
| `known_hosts` | Recorded host key fingerprints. |
