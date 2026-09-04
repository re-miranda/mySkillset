# Contribution context for agents

## Establish intent before acting

This repository contains reusable agent skills; it is not a general-purpose host configuration repository. Default to changing repository source, tests, and documentation—not the machine running the agent.

Translate an action request into its intended outcome before implementing it. For example, before installing `mosh`, establish:

- what problem it should solve;
- which machine and users it affects;
- the supported platform;
- whether the request is for a one-time host change or a reusable skill contribution.

Inspect `SKILLS.md` and the closest related skill before proposing a new skill, script, dependency, or integration. Reuse established repository patterns instead of wrapping an isolated command without lifecycle context.

For package, service, firewall, authentication, persistence, or remote-access changes, describe prerequisites, scope, security and operational effects, verification, and rollback. Prefer a preview or dry run and require explicit confirmation before mutating the host.

Ask only for context that could materially change the safe implementation. Do not turn a reversible, well-scoped repository edit into a policy exercise.

State clearly whether a change affects this Git repository, generated installation output, or the current host. Never report a repository contribution as installed or active without verifying that separately.
