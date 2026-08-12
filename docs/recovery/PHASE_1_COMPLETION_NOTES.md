# Phase 1 Completion Notes

Phase 1 is partially complete in source control. To fully complete it, run the
following on a private E-JUST staging VM. Do not use the Windows workstation as
the production host and do not paste passwords, API keys, or private keys into
this repository or chat.

## 1. Prepare the VM

Create an Ubuntu Server 22.04 LTS amd64 VM with outbound access to the
university-approved package mirrors. Log in with an account that can use
`sudo`, then clone the repository into a normal application directory (for
example `/opt/anyplace/source`).

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg git unzip zip make g++ \
  openjdk-17-jdk python3 imagemagick advancecomp netcat-openbsd
```

Install Node.js 22 with npm 10 and MongoDB Community 6.0.x from the
university-approved mirrors. Install the legacy web command-line tools:

```bash
sudo npm install --global grunt-cli@1.5.0 bower@1.8.14
```

## 2. Obtain authorized submodule access

Ask the E-JUST GitHub/repository administrator to grant the VM’s deployment
account read access to the two Anyplace library repositories. Create a dedicated
SSH deploy key on the VM and give only its public key to that administrator.
After access is granted, verify it without revealing the private key:

```bash
ssh -T git@github.com
git submodule update --init --recursive
test -f clients/android-new/lib-android/build.gradle
test -f clients/core/lib/build.gradle
```

Both `test` commands must exit with status `0`. Do not replace missing
submodules with copied code or public forks.

## 3. Run the preflight

From the repository root, run:

```bash
scripts/verify-ubuntu-toolchain.sh
scripts/verify-ubuntu-toolchain.sh --with-android
```

Both commands must print `PASS`. If one fails, install only the tool/version it
names, then rerun it. The required version matrix is in
[`UBUNTU_22.04_TOOLCHAIN.md`](UBUNTU_22.04_TOOLCHAIN.md).

## 4. Record evidence safely

Record the VM Ubuntu version, `java -version`, `node --version`, `npm --version`,
and successful preflight output in the university’s private operations record.
Do not record secrets, MongoDB connection strings with passwords, or private SSH
keys. Send the non-sensitive pass/fail results back for the recovery audit.

MongoDB authentication, localhost binding, backend startup, and application
builds are Phase 2 work. Do not make the database public while preparing Phase
1.
