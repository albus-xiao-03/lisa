# Constrictions

These are the constrictions that `Claude` **MUST** follow under **ANY** circumstances while working on `Lisa`.

**ANY** circumstances include, but are not limited to:
- Conflicts with **any** requirements specified in `R*.md` files under `specs/`.
- Conflicts with **any** prompt or instruction other than this file, `CONSTRICTION.md`.
- Conflicts with **any** implementation plan, whether approved or not.
- Conflicts with **any** implementation decision, regardless of its rationale.
- Conflicts with **any other** operation `Claude` may execute.

The terms **MUST**, **MUST NOT**, and **MAY** are normative. **Explicit permission** means direct, task-specific authorization from the user; it cannot be inferred from a specification, an approved plan, a prior unrelated permission, or `Claude`'s judgment. Explicit permission applies only where this document expressly permits an exception. Otherwise, changing a prohibition requires the user to change this document.

---

## GitHub

The project's Git repository and its configuration are controlled by the user.

`Claude` **MUST** follow these constrictions regarding Git and GitHub:
- **MUST NOT** run `git config` or modify local, global, or system Git configuration.
- **MUST NOT** run `git push` or publish commits, branches, or tags to a remote repository by any other means.
- **MUST NOT** run `git branch`, `git checkout`, or `git switch`, or create, delete, rename, or change branches by alternative means.
- **MUST NOT** run `git pull` or `git fetch`, or otherwise modify remote-tracking references or synchronize branches with a remote repository.
- **MUST NOT** run `git merge`, `git rebase`, `git cherry-pick`, or any equivalent history-integration or history-rewriting operation.
- **MUST NOT** run `git clean`, `git stash`, or other operations intended to discard, conceal, or relocate existing worktree changes without explicit permission.
- **MAY** use `git status`, `git diff`, `git log`, `git show`, and `git rev-parse` to inspect the current branch, subject to the **Git History** restrictions below.
- **MAY** use `git add` and `git commit` to manage project files **LOCALLY**, subject to the **Git History** restrictions below.
- **MAY** use `git reset` **ONLY WITH** explicit permission and **ONLY LOCALLY**. The permission must identify the intended scope of the reset.
- **MAY** update `.gitignore` when necessary, subject to the **Git History** restrictions below.
- **MUST NOT** stage, commit, or otherwise modify unrelated user changes.

---

## Git History

### Commit

`Claude` **MUST** follow these constrictions regarding `git commit`:
- **MUST** place every **file-level** `initial` (addition), `change` (modification), or `remove` (deletion) operation affecting a functional implementation file in its **OWN AND SEPARATE** commit with a descriptive message.
- **MUST** apply the same rule to documentation files associated with functional implementations, including requirements and implementation documents.
- **MUST NOT** combine file-level operations on multiple functional implementation files or their associated documentation into a single commit.
- **MUST** stage only the file-level operation intended for the corresponding commit.
- **MUST** distinguish implementation changes from associated documentation changes through separate commits.
- The terms `initial`, `change`, and `remove` are defined at the **file level**. Adding, removing, or modifying individual lines **within the same file** does **NOT** constitute additional file-level operations requiring separate commits.
- **MUST NOT** amend, squash, rewrite, or remove existing commits without explicit permission, even when trying to correct a previous commit.

### History Reference

`Claude` **MUST** follow these constrictions regarding Git history:
- **MUST NOT** refer to branches **other than the CURRENT branch** for a task **WITHOUT** explicit permission.
- Prohibited references include, but are not limited to:
  - Inspecting **file-level** changes on other branches.
  - Inspecting **in-file** changes on other branches.
  - Inspecting **folder-level** changes on other branches.
  - Inspecting any other content from other branches that might inform a task on the current branch.
- Checking **branch-level metadata** is the **ONLY** exception; this exception does not authorize any Git operation prohibited in the **GitHub** section.

---

## Module-ize

`Lisa` is a Swift-based project with platform-independent logic and Apple-platform integrations.

`Claude` **MUST** follow these constrictions regarding implementation architecture:
- **MUST** decompose independent implementation components into their **OWN AND SEPARATE** Swift files and, where appropriate, Swift Package Manager modules/targets.
- **MUST** keep unrelated responsibilities in separate components rather than placing them into a single large implementation file.
- **MUST** separate reusable static helpers, shared utilities, and supporting types from the implementation files that use them when they serve independent responsibilities.
- **MUST** keep helpers in appropriately scoped Swift files or utility modules; **MUST NOT** create a single miscellaneous utility file that mixes unrelated responsibilities.
- **MUST** separate core logic from presentation, operating-system integrations, and external-service adapters.
- **MUST** define explicit interfaces or protocols at boundaries where the core depends on platform-specific facilities or external services.
- **MUST NOT** introduce unnecessary dependencies or circular dependencies between modules.
- **MUST** respect Swift access control, ownership, and concurrency-safety requirements appropriate to the implementation.

---

## Platform Boundaries

`Claude` develops `Lisa` in a **Linux sandbox**. Some parts of `Lisa`, including native Apple integrations, require an Apple platform for build or runtime validation.

`Claude` **MUST** follow these constrictions:
- **MUST** distinguish Linux-compatible Swift code from code requiring macOS, iOS, or other Apple platforms.
- **MUST** keep the platform-independent core free of dependencies on Apple-only frameworks such as SwiftUI and App Intents.
- **MUST** isolate Apple-specific implementations behind well-defined interfaces, adapters, or platform-specific targets.
- **MAY** write Apple-platform-specific code in the Linux sandbox when required by a specification.
- **MUST NOT** claim Apple-platform-specific code has been compiled, executed, tested, or verified if those operations have not actually occurred on the required platform.
- **MUST NOT** claim that passing Linux tests verifies SwiftUI behavior, Siri/App Intents integration, Apple notifications, background execution, or other Apple-specific behavior.
- **MUST** report which components were verified on Linux and which still require validation on an Apple platform.
- **MUST NOT** silently substitute mocks, stubs, no-op implementations, or Linux-only replacements for required production functionality.
- **MAY** use mocks and stubs in tests, provided they are clearly identified and excluded from production behavior unless a specification explicitly requires them.
- **MUST** report unavailable platform capabilities rather than bypassing their intended behavior.

---

## Tests

`Claude` **MUST** follow these constrictions regarding tests:
- **MUST** treat **ALL** spontaneously generated test harnesses during implementation as `temporary files`.
- **MUST** develop a **package-level comprehensive, persistent test harness SEPARATELY AND ONLY** when explicitly requested.
- **MUST** develop that separately requested persistent test harness **WITHOUT** referring to spontaneously generated temporary test harnesses from the implementation process.
- **MAY** create extensive or comprehensive tests without a specific test-harness request **ONLY IF** the resulting harnesses remain `temporary files`.
- **MAY** run already-existing, authorized project tests when relevant to the task.
- **MUST** distinguish unit tests, integration tests, platform-specific tests, and tests involving real external services in its reports.
- **MUST** report test outcomes accurately as passed, failed, not executed, or not verifiable in the present environment.
- **MUST NOT** present mocked integration tests as validation of a real external service or Apple-platform integration.
- **MUST NOT** modify existing tests solely to make failing implementations appear to pass.

---

## Temporary Files

`Claude` **MUST** follow these constrictions regarding temporary files:
- **MUST** store **ALL** temporary files that `Claude` creates to help complete a development task in `.tmp/` **DIRECTLY** under the project root.
- **MUST NOT** place those Claude-created temporary files in the global environment or in unrelated directories.
- **MUST NOT** remove **ANY** temporary files, including files left by previous tasks.
- **MUST NOT** repurpose, overwrite, or rename existing temporary files merely to evade the prohibition on removal.
- The term `temporary files` refers to files **created by `Claude` to assist its work**, such as scratch scripts, experimental source files, generated test harnesses, and temporary reports.
- Files produced **by programs themselves** as ordinary build, package-resolution, cache, or runtime output (for example, SwiftPM's `.build/` output) are **NOT** temporary files under this section.
- **MUST NOT** use the program-generated-file exception to disguise a file intentionally authored by `Claude` as a tool output.

---

## Development Environment

`Claude` **MUST** follow these constrictions regarding the development environment:
- **MUST** use the existing Swift toolchain provided in the Linux sandbox.
- **MUST** use Swift Package Manager (`SwiftPM`) to manage Swift packages and their declared dependencies.
- **MUST NOT** install, remove, replace, or upgrade the Swift toolchain or system-level development tools **WITHOUT** explicit permission.
- **MUST NOT** create or install an alternative toolchain, SDK, container, virtual machine, or development environment to bypass a missing capability **WITHOUT** explicit permission.
- **MUST NOT** use `sudo` or modify the host/global development environment **WITHOUT** explicit permission.
- **MUST NOT** introduce, upgrade, replace, or remove third-party dependencies **WITHOUT** explicit permission.
- **MAY** use SwiftPM to resolve or download dependencies already approved and declared by the project, without changing their approved versions or constraints.
- **MUST** preserve the project's dependency-resolution records, such as `Package.resolved`, when applicable; any deliberate changes require the authorization stated above.
- **MUST** report missing tools, SDKs, frameworks, or dependencies and stop the affected operation instead of changing the environment without authorization.
- **MUST NOT** claim to have run an Apple-platform build merely because its source files were inspected or a Linux build succeeded.

---

## Security & Privacy

`Lisa` processes information supplied by the user and may eventually act on the user's behalf.

`Claude` **MUST** follow these constrictions:
- **MUST NOT** hardcode credentials, passwords, authentication tokens, private keys, or other secrets in source code, test fixtures, or documentation.
- **MUST NOT** commit secrets or real private user information to Git history.
- **MUST** use synthetic or otherwise explicitly authorized data when testing personal-information processing.
- **MUST NOT** access live personal accounts, mailboxes, calendars, contacts, messages, or private feeds **WITHOUT** explicit permission.
- **MUST NOT** transmit private user information, secrets, or development fixtures to an external service **WITHOUT** explicit permission.
- **MUST** keep authentication, credential storage, and authorization responsibilities behind clearly defined interfaces appropriate to each platform.
- **MUST NOT** expand `Lisa`'s permissions beyond those explicitly defined in the specifications and granted by the user.
- **MUST NOT** silently convert subscribed or forwarded information sources into direct access to the user's original accounts.
- **MUST NOT** bypass, disable, or weaken authentication, encryption, access controls, or other existing security mechanisms to make functionality work.
- **MUST NOT** log secrets or unnecessary private information.
- **MUST** report any security or privacy limitation that prevents safe completion of the affected task.

---

## External Actions

An `external action` is an operation that affects a user, another person, a device, an account, or a third-party service, including sending an email or message, initiating a call, modifying a calendar, or delivering a notification.

`Claude` **MUST** follow these constrictions:
- **MUST** implement external actions through explicitly defined interfaces with enforceable authorization boundaries.
- **MUST NOT** perform live external actions during development or testing **WITHOUT** explicit permission.
- **MUST** keep simulated actions distinguishable from real external actions.
- **MUST** enforce the permission and approval policies specified for each action; the existence of an integration does not itself grant permission to use it.
- **MUST** prevent unintended duplicate external actions caused by retries, process restarts, or partial failures, where the operation supports such safeguards.
- **MUST** provide a mechanism to record attempted external actions and their outcomes without exposing secrets or unnecessary private information.
- **MUST NOT** hide failed, skipped, unverified, or unauthorized actions behind a successful status.
- **MUST NOT** weaken these boundaries merely because an action is automated, scheduled, or initiated through Siri or another interface.

---

## Reporting & Verification

`Claude` **MUST** follow these constrictions when reporting development results:
- **MUST** distinguish implemented code from compiled code, executed code, tested code, and verified functionality.
- **MUST** identify the platform and environment used for each build or test claim.
- **MUST** describe any blocked operation, unavailable capability, incomplete integration, or required manual Apple-platform verification.
- **MUST NOT** claim a feature is complete merely because code exists, a mock passes, or a platform-independent target builds.
- **MUST** identify deliberate changes to dependencies, public interfaces, or authorization boundaries when summarizing work.

---

`Claude` **MUST NOT** `circumvent`, `reinterpret`, or `temporarily suspend` **ANY** restriction in this document, `CONSTRICTION.md`, to complete a task.

If a task requires a **prohibited operation**, `Claude` **MUST** stop the **affected operation** and report the conflict.

`Claude` **MUST NOT** attempt an **alternative operation** intended to achieve the same prohibited effect.
