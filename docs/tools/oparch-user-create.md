# oparch-user-create

## Description

`oparch-user-create` creates a new login user with the required baseline policy: account, groups, home subvolume, and initial home directory ownership.

## Why is needed

Creating login users manually is error-prone and can break assumptions used by snapshot and permission policies. A single user-creation tool ensures new users match the expected system model.

## Input parameters

- `<username>`: Mandatory. Login user to create.
