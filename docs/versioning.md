# Contract Versioning

This document outlines the versioning mechanism for the DeepBook Wrapper contract. The system is designed to allow for safe upgrades of the contract logic while interacting with a single, persistent `Wrapper` object.

## Motivation

The primary motivation for implementing versioning is to provide a secure and flexible upgrade path for the contract.

Key scenarios where versioning is crucial include:

- **Forced Upgrades**: In the event of a critical issue or a major feature update, a new contract version can be deployed. The old version can then be disabled, compelling all clients to upgrade to the new, improved version.
- **Security Patches**: If a vulnerability is discovered, a patched version of the contract can be quickly deployed and enabled, while the vulnerable version is disabled, mitigating the risk promptly.
- **Phased Rollouts**: Versioning allows for new features to be rolled out gradually. A new version can coexist with an old one, allowing for a smoother transition period for users.

## Scope of Versioning

The `deepbook-wrapper` package contains two shared objects: `Wrapper` and `CreatePoolConfig`. The versioning mechanism described in this document applies **only** to the `Wrapper` object.

The `CreatePoolConfig` object is not versioned. This is because it can only be modified by an administrator, and there are no functions available for users to create new `CreatePoolConfig` objects.

## Core Concepts

The versioning is built upon four main components:

1.  **`Wrapper.allowed_versions`**: The central `Wrapper` object contains a field named `allowed_versions`. This is a `VecSet<u16>` that stores a list of all package versions permitted to interact with it.

2.  **`CURRENT_VERSION`**: Each deployed version of the `deepbook-wrapper` package has a `CURRENT_VERSION` constant (a `u16`) defined in `packages/deepbook-wrapper/sources/helper.move`. This constant uniquely identifies the version of that specific package's code.

3.  **`verify_version()` Check**: Most functions that mutate the `Wrapper` state begin with a call to `verify_version()`. This internal function reads its own package's `CURRENT_VERSION` and checks if that version number is present in the `Wrapper`'s `allowed_versions` set. If the version is not found, the transaction aborts with the error `EPackageVersionNotEnabled`.

4.  **`Wrapper.disabled_versions`**: The `Wrapper` object also contains a `disabled_versions` `VecSet<u16>`. This acts as a permanent denylist. Once a version number is added to this set, it can never be re-enabled.

## Upgrade and Version Management Process

The process for upgrading the contract and managing which versions are active is controlled by an administrator.

### Standard Upgrade Procedure

The typical process for rolling out a new version follows these steps:

1.  **Make Code Changes**: Implement the required features or fixes in the contract source code that necessitate a version update.
2.  **Increment Version**: Update the `CURRENT_VERSION` constant in `packages/deepbook-wrapper/sources/helper.move` to a new, unique number.
3.  **Deploy New Package**: Deploy the updated package to the network. This action results in a new package object with a unique ID.
4.  **Enable New Version**: Using the newly deployed package, an administrator calls `enable_version`. This action adds the new version to the `Wrapper` object's `allowed_versions` set and emits a `VersionEnabled` event.
5.  **Disable Old Version**: To complete the upgrade, an administrator calls `disable_version` to remove the old version number. It is crucial that this call is also made from the **new package**. This is an irreversible action that moves the version to the `disabled_versions` denylist and emits a `VersionDisabled` event.

### Motivation for Irreversible Disabling
The decision to make disabling a version permanent is intentional and serves as a critical security measure to prevent human error.
A version might be disabled because it contains a vulnerability.
Over time, the specific reasons might be forgotten. To prevent a bad actor, who could somehow gain access to the `AdminCap`, from re-enabling a vulnerable version and exploiting it, we make it impossible to re-enable it again.

This security measure does not reduce flexibility. In case we need to use an old implementation for some reason, we can still take the code from an old commit, deploy it as a new package with a new `CURRENT_VERSION`, and enable that new version.

### Safety Constraints
- A version can **never** be re-enabled once it has been disabled.
- An administrator cannot disable the currently executing version of the package. An attempt to do so will cause the transaction to revert.

### Example Scripts

The repository provides example scripts that demonstrate how to perform these administrative actions:
-   `examples/wrapper/versions/enable-version.ts`
-   `examples/wrapper/versions/disable-version.ts`

These scripts show how to construct and send the transactions to call the `enable_version` and `disable_version` functions.
